using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp;
using Newtonsoft.Json.Linq;

namespace Kari.GeneratorCore.Workflow
{
    public class MasterEnvironment : Singleton<MasterEnvironment>
    {
        public string CommonProjectName { get; set; } = "Common"; 
        public string GeneratedDirectorySuffix { get; set; } = "Generated";
        public IFileWriter GlobalFileWriter { get; set; }
        public string GeneratedNamespaceSuffix => GeneratedDirectorySuffix;

        public ProjectEnvironmentData CommonPseudoProject { get; private set; }
        public ProjectEnvironmentData RootPseudoProject { get; private set; }

        public INamespaceSymbol RootNamespace { get; private set; }
        public Compilation Compilation { get; private set; }
        public RelevantSymbols Symbols { get; private set; }

        public readonly Logger Logger;
        public readonly CancellationToken CancellationToken;
        public readonly string RootNamespaceName;
        public readonly string ProjectRootDirectory;
        public readonly List<ProjectEnvironment> Projects = new List<ProjectEnvironment>();
        public readonly List<IAdministrator> Administrators = new List<IAdministrator>(5);

        /// <summary>
        /// Initializes the MasterEnvironment and replaces the global singleton instance.
        /// </summary>
        public MasterEnvironment(string rootNamespace, string rootDirectory, CancellationToken cancellationToken, Logger logger)
        {
            CancellationToken = cancellationToken;
            RootNamespaceName = rootNamespace;
            ProjectRootDirectory = rootDirectory;
            Logger = logger;
        }

        public void InitializeCompilation(ref Compilation compilation)
        {
            compilation = compilation.AddSyntaxTrees(
                Administrators.Select(a => 
                    CSharpSyntaxTree.ParseText(a.GetAnnotations())));
            Symbols = new RelevantSymbols(compilation);
            Compilation = compilation;
            RootNamespace = compilation.TryGetNamespace(RootNamespaceName);

            // TODO: log instead?
            if (RootNamespace is null) throw new System.Exception($"No such namespace {RootNamespaceName}");
        }

        private void AddProject(ProjectEnvironment project)
        {
            Projects.Add(project);
            if (project.NamespaceName == CommonProjectName)
            {
                CommonPseudoProject = project;
            }
        }

        public void FindProjects()
        {
            // TODO: log instead?
            if (GlobalFileWriter is null) throw new System.Exception("The file writer must have been set by now.");

            // find asmdef's
            foreach (var asmdef in Directory.EnumerateFiles(ProjectRootDirectory, "*.asmdef", SearchOption.AllDirectories))
            {
                var projectDirectory = Path.GetDirectoryName(asmdef);
                var fileName = Path.GetFileNameWithoutExtension(asmdef);

                // We in fact have a bunch more info here that we could use.
                var asmdefJson = JObject.Parse(File.ReadAllText(asmdef));

                string namespaceName;
                if (asmdefJson.TryGetValue("name", out JToken nameToken))
                {
                    namespaceName = nameToken.Value<string>();
                    // TODO: Report bettter
                    Debug.Assert(!(namespaceName is null));
                }
                else
                {
                    // Assume such naming convention.
                    namespaceName = fileName;
                }

                // Even the editor project will have this namespace, because of the convention.
                INamespaceSymbol projectNamespace = Compilation.TryGetNamespace(namespaceName);
                
                if (projectNamespace is null)
                {
                    // TODO: Report this in a better way
                    System.Console.WriteLine($"The namespace {namespaceName} deduced from asmdef project {fileName} could not be found in the compilation.");
                    continue;
                }

                // Check if any script files exist in the root
                if (Directory.EnumerateFiles(projectDirectory, "*.cs", SearchOption.TopDirectoryOnly).Any()
                    // Check if any folders exist besided Editor folder
                    || Directory.EnumerateDirectories(projectDirectory).Any(path => !path.EndsWith("Editor")))
                {
                    var environment = new ProjectEnvironment(
                        directory:      projectDirectory,
                        namespaceName:  namespaceName,
                        rootNamespace:  projectNamespace,
                        fileWriter:     GlobalFileWriter.GetProjectWriter(projectDirectory));
                    // TODO: Assume no duplicates for now, but this will have to be error-checked.
                    AddProject(environment);
                }

                // Check if "Editor" is in the array of included platforms.
                // TODO: I'm not sure if not-editor-only projects need this string here.
                if (!asmdefJson.TryGetValue("includePlatforms", out JToken platformsToken)
                    || !platformsToken.Children().Any(token => token.Value<string>() == "Editor"))
                {
                    continue;
                }

                // Also, add the editor project as a separate project.
                // We take the convention that the namespace would be the same as that of asmdef, but with and appended .Editor.
                // So any namespace within project A, like A.B, would have a corresponding editor namespace of A.Editor.B
                // rather than A.B.Editor. 

                var editorProjectNamespace = projectNamespace.GetNamespaceMembers().FirstOrDefault(n => n.Name == "Editor");
                if (editorProjectNamespace is null)
                    continue;
                var editorDirectory = Path.Combine(projectDirectory, "Editor");
                if (!Directory.Exists(editorDirectory))
                {
                    // TODO: better error handling
                    System.Console.WriteLine($"Found an editor project {namespaceName}, but no `Editor` folder.");
                    continue;
                }
                var editorEnvironment = new ProjectEnvironment(
                    directory:      editorDirectory,
                    namespaceName:  namespaceName.Combine("Editor"),
                    rootNamespace:  editorProjectNamespace,
                    fileWriter:     GlobalFileWriter.GetProjectWriter(editorDirectory));
                    
                AddProject(editorEnvironment);
            }
            
            InitializePseudoProjects();
        }

        public void InitializePseudoProjects()
        {
            if (Projects.Count == 0)
            {
                var rootProject = new ProjectEnvironment(
                    directory:      ProjectRootDirectory,
                    namespaceName:  RootNamespaceName,
                    rootNamespace:  RootNamespace,
                    fileWriter:     GlobalFileWriter);
                Projects.Add(rootProject);
                RootPseudoProject = rootProject;
            }
            else
            {
                RootPseudoProject = new ProjectEnvironmentData(
                    directory:      ProjectRootDirectory,
                    namespaceName:  RootNamespaceName,
                    fileWriter:     GlobalFileWriter,
                    logger:         new Logger("Root")
                );
            }

            if (CommonPseudoProject is null) 
            {
                if (CommonProjectName is null) 
                {
                    CommonPseudoProject = RootPseudoProject;
                }
                else 
                {
                    throw new System.Exception($"No common project {CommonProjectName}");
                }
            }
        }

        public void InitializeAdministrators()
        {
            foreach (var admin in Administrators)
            {
                admin.Initialize();
            }
        }

        public Task Collect()
        {
            var cachingTasks = Projects.Select(project => project.Collect());
            var managerTasks = Administrators.Select(admin => admin.Collect());
            return Task.Factory.ContinueWhenAll(
                cachingTasks.ToArray(), (_) => Task.WhenAll(managerTasks), CancellationToken);
        }

        public void RunCallbacks()
        {
            var infos = new List<CallbackInfo>(); 
            foreach (var admin in Administrators)
            foreach (var callback in admin.GetCallbacks())
            {
                infos.Add(callback);
            }

            infos.Sort((a, b) => a.Priority - b.Priority);

            for (int i = 0; i < infos.Count; i++)
            {
                infos[i].Callback();
            }
        }

        public Task GenerateCode()
        {
            var managerTasks = Administrators.Select(admin => admin.Generate());
            return Task.WhenAll(managerTasks);
        }
    }

    public readonly struct CallbackInfo
    {
        public readonly int Priority;
        public readonly System.Action Callback;

        public CallbackInfo(int priority, System.Action callback)
        {
            Priority = priority;
            Callback = callback;
        }
    }
}