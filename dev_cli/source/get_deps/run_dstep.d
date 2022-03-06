module get_deps.run_dstep;

import jcli;

@Command("dstep", "Runs dstep on libgit2")
struct RunDStep
{
    @ArgNamed
    string libgit2Path = "third_party/libgit2";

    @ArgNamed
    string dstepExePath = "build/bin/dstep.exe";

    @ArgNamed
    string outputPath = "build/libgit2-d";

    @ArgRaw
    string[] rawArgs;

    void onExecute()
    {
        import std.file;
        import std.path;
        import std.algorithm;
        import std.range;
        import std.process;
        import std.stdio;
        import common;

        const libgit2FullPathPath = absolutePath(buildNormalizedPath(libgit2Path));
        // dstepExePath = absolutePath(buildNormalizedPath(dstepExePath));
        outputPath = absolutePath(buildNormalizedPath(outputPath));

        const headerRootFullPath = libgit2FullPathPath.buildPath("include");
        const headerRootRelativePath = libgit2Path.buildPath("include");

        auto headerPaths = headerRootRelativePath
            .dirEntries(SpanMode.depth)
            .filter!(a => isFile(a) && extension(a) == ".h")
            .map!(a => a[headerRootRelativePath.length + 1 .. $]);

        string[] getArgs(string filePath)
        {
            return [dstepExePath, filePath, 
                "-I" ~ headerRootFullPath,
                "-o", outputPath.buildPath(setExtension(filePath, ".d"))]
                    .chain(rawArgs)
                    .array;
        }
        foreach (headerFilePath; headerPaths)
        {
            auto args = getArgs(headerFilePath);
            writeln(escapeShellCommand(args));
            auto pid = spawnProcess2(args, headerRootFullPath);
            wait(pid);
        }
    }
}