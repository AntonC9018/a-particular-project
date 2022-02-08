module app;

import std.stdio;
import std.experimental.logger;

int main(string[] args)
{
	if (args.length == 1)
	{
		writeln("Usage: `dev subcommand`");
		return 0;
	}

	string commandName = args[1];
	switch (commandName)
	{
		default:
        {
			writeln("No such command ", commandName);
			return 1;
        }

        case "cwd":
        {
            static import std.file;
            writeln(std.file.getcwd);
            return 0;
        }

        case "getDeps":
        {
            import get_deps.stuff;
            import std.path;
            static import std.file;
            const rootFolder = std.file.getcwd;
            bool dstepSuccess = 
            {
                DStepParams params = 
                {
                    clonedRepoPath:                     buildPath(rootFolder, "dstep"),
                    dstepExeOutputPath:                 buildPath(rootFolder, "build", "bin", "dstep.exe"),
                    whetherToCleanUpTheRepoAfterBuild:  false,
                    whetherToClearExistingClonedRepo:   false,
                    whetherToSkipIfAlreadyBuilt:        true,
                };
                return buildDStep(params);
            }();

            bool libgitSuccess =
            {
                Libgit2Params params =
                {
                    clonedRepoPath:                     buildPath(rootFolder, "libgit2"),

                    // it should be right next to the executable, which is why it's not relative to the root folder.
                    libgitLibOutputPath:                buildPath(dirName(std.file.thisExePath), "git2.dll"),

                    libgitDllOutputPath:                buildPath(rootFolder, "lib", "git2.lib"),
                    cmakeBuildDirectory:                buildPath(rootFolder, "build", "libgit2"),
                    whetherToCleanUpTheRepoAfterBuild:  false,
                    whetherToClearExistingClonedRepo:   false,
                    whetherToSkipIfAlreadyBuilt:        true
                };
                return buildLibgit2(params);
            }();

            if (libgitSuccess && dstepSuccess)
            {
                log("good");
                return 0;
            }
            return 1;
        }

		version (MainStuff)
        {
            case "gitPrecommitHook":
                return gitPrecommitHook();
        }
	}
}

version (MainStuff):

int gitPrecommitHook()
{
	return 0;
}
