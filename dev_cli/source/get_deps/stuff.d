module get_deps.stuff;

struct Options
{
    string buildOutputPath = "build";
    string binOutputPath = "build";
    string libOutputPath = "lib";
}

import std.process;
static import std.file;
import std.path;
import std.experimental.logger;
import common;

import acd.versions : Versions;
mixin Versions;


bool tryGitPull(string clonedRepoPath, string errorTitle)
{
    log("Pulling the repo at ", clonedRepoPath);
    auto pullingProcess = spawnProcess2(["git", "pull"], clonedRepoPath);
    const status = wait(pullingProcess);
    if (status != 0)
    {
        error(errorTitle, "could not pull the existing repository. You may want to delete it.");
        return false;
    }
    return true;
}


bool tryGitClone(string repoURL, string clonedRepoPath, string errorTitle)
{
    log("Cloning the repo at ", repoURL);
    auto pid = spawnProcess(["git", "clone", "--recursive", repoURL, clonedRepoPath]);
    const status = wait(pid);
    if (status != 0)
    {
        error(errorTitle, "failed to clone ", repoURL);
        return false;
    }
    return true;
}

bool maybeCloneRepo(
    string repoURL,
    string clonedRepoPath,
    /// The thing printed before the error is printed.
    /// E.g. `Hello World: error text`.
    string errorTitle,
    bool whetherToClearExistingClonedRepo)
{
    if (whetherToClearExistingClonedRepo)
    {
        log("Removing cloned repo at", clonedRepoPath);
        std.file.rmdirRecurse(clonedRepoPath);

        if (!tryGitClone(repoURL, clonedRepoPath, errorTitle))
            return false;
    }
    else if (std.file.exists(clonedRepoPath)
        && std.file.isDir(clonedRepoPath))
    {
        if (!tryGitPull(clonedRepoPath, errorTitle))
            return false;
    }
    else
    {
        if (!tryGitClone(repoURL, clonedRepoPath, errorTitle))
            return false;
    }
    return true;
}


struct DStepParams
{
    string clonedRepoPath;
    string dstepExeOutputPath;
    string buildMode = "release";
    bool whetherToClearExistingClonedRepo;
    bool whetherToSkipIfAlreadyBuilt;
    bool whetherToCleanUpTheRepoAfterBuild;
}

bool buildDStep(in DStepParams params)
{
    string errorTitle = "Failed to build DStep: ";

    // Validate
    {
        bool anyNotFound = false;
        if (!canFindProgram("git"))
        {
            error(errorTitle, "`git` cannot be invoked.");
            anyNotFound = true;
        }

        if (!canFindProgram("dub"))
        {
            error(errorTitle, "`dub` cannot be invoked.");
            anyNotFound = true;
        }

        if (!canFindProgram("clang"))
        {
            error(errorTitle, "`clang` cannot be invoked. DStep needs libclang to build. Download the compiled binaries of either dstep or clang if you don't want to build it manually.");
            anyNotFound = true;
        }

        if (anyNotFound)
            return false;
    }
    
    string dstepExecutableName = Version.Windows ? "dstep.exe" : "dstep";
    string builtDStepExecutablePath = buildPath(params.clonedRepoPath, "bin", dstepExecutableName);
    bool shouldRebuild = 
    {
        if (params.whetherToSkipIfAlreadyBuilt)
        {
            if (std.file.exists(params.dstepExeOutputPath))
            {
                log("Skipping building DStep, already built.");
                return false;
            }

            if (std.file.exists(builtDStepExecutablePath))
            {
                log("Found a prebuilt dstep.exe at ", builtDStepExecutablePath);
                replaceFile(builtDStepExecutablePath, params.dstepExeOutputPath);
                return false;
            }
            else
            {
                logf("Did not find a prebuilt dstep at either % or % so will build again.", builtDStepExecutablePath, params.dstepExeOutputPath);
            }
        }
        return true;
    }();

    if (shouldRebuild)
    {
        // Clone
        {
            const repoURL = "https://github.com/jacob-carlborg/dstep";
            if (!maybeCloneRepo(
                repoURL,
                params.clonedRepoPath,
                errorTitle,
                params.whetherToClearExistingClonedRepo))
            {
                return false;   
            }
        }

        // Build
        {
            {
                auto pid = spawnProcess2(
                    ["dub", "build", "--build", params.buildMode],
                    params.clonedRepoPath);
                const status = wait(pid);
                if (status != 0)
                {
                    error(errorTitle, "failed to build with dub.");
                    return false;
                }
            }

            if (!std.file.exists(builtDStepExecutablePath))
            {
                error(errorTitle, "expected to find dstep.exe at ", builtDStepExecutablePath);
                return false;
            }

            maybeCreateDirectoriesUntilDirectoryOf(params.dstepExeOutputPath);
            replaceFile(builtDStepExecutablePath, params.dstepExeOutputPath);
        }
    }

    if (params.whetherToCleanUpTheRepoAfterBuild)
    {
        std.file.rmdirRecurse(params.clonedRepoPath);
    }
    
    return true;
}



struct Libgit2Params
{
    string clonedRepoPath;
    
    string libgitLibOutputPath;
    string libgitDllOutputPath;

    string cmakeBuildDirectory;
    string buildMode = "Release";
    bool whetherToClearExistingClonedRepo;
    bool whetherToSkipIfAlreadyBuilt;
    bool whetherToCleanUpTheRepoAfterBuild;
}


bool buildLibgit2(in Libgit2Params params)
{
    string errorTitle = "Failed to build Libgit2: ";

    // Validate
    {
        bool anyNotFound = false;
        if (!canFindProgram("git"))
        {
            error(errorTitle, "`git` cannot be invoked.");
            anyNotFound = true;
        }

        if (!canFindProgram("cmake"))
        {
            error(errorTitle, "`cmake` cannot be invoked.");
            anyNotFound = true;
        }

        if (anyNotFound)
            return false;
    }

    // Ideally should do like the func above does.
    if (params.whetherToSkipIfAlreadyBuilt)
    {
        if (std.file.exists(params.libgitDllOutputPath)
            && std.file.exists(params.libgitLibOutputPath))
        {
            log("Skipping building Libgit2, already built.");
            return true;
        }
    }

    // Clone
    {
        const repoURL = "https://github.com/libgit2/libgit2";
        if (!maybeCloneRepo(
            repoURL,
            params.clonedRepoPath,
            errorTitle,
            params.whetherToClearExistingClonedRepo))
        {
            return false;   
        }
    }

    // Build
    {
        const cmakeContainsNonAsciiMessage = "Check if your path contains only ascii characters.";
        {
            auto pid = spawnProcess([
                "cmake",
                "-B" ~ params.cmakeBuildDirectory,
                "-H" ~ params.clonedRepoPath,
                "-DCMAKE_BUILD_TYPE=" ~ params.buildMode]);
            const status = wait(pid);
            if (status != 0)
            {
                error(errorTitle, "failed to generate CMake build files. ", cmakeContainsNonAsciiMessage);
                return false;
            }
        }
        {
            auto pid = spawnProcess([
                "cmake",
                "--build", params.cmakeBuildDirectory,
                "--config", params.buildMode]);
            const status = wait(pid);
            if (status != 0)
            {
                error(errorTitle, "failed to run CMake. ", cmakeContainsNonAsciiMessage);
                return false;
            }
        }
        
        {
            string cmakeOutputPath = buildPath(params.cmakeBuildDirectory, params.buildMode);

            bool checkMoveStuff(string outputFileName, string outputFileMoveToName)
            {
                std.file.mkdirRecurse(dirName(params.libgitLibOutputPath));
                std.file.mkdirRecurse(dirName(params.libgitLibOutputPath));

                string outputFileFullPath = buildPath(cmakeOutputPath, outputFileName);
                if (!std.file.exists(outputFileFullPath))
                {
                    error(errorTitle, "expected to find ", outputFileName, " at ", outputFileFullPath);
                    return false;
                }
                maybeCreateDirectoriesUntilDirectoryOf(outputFileMoveToName);
                replaceFile(outputFileFullPath, outputFileMoveToName);
                return true;
            }

            bool libGood = checkMoveStuff(Version.Windows ? "git2.lib" : "git2.o", params.libgitLibOutputPath);
            bool dllGood = checkMoveStuff(Version.Windows ? "git2.dll" : "git2.so", params.libgitDllOutputPath);

            if (!libGood || !dllGood)
                return false;
        }

        if (params.whetherToCleanUpTheRepoAfterBuild)
        {
            std.file.rmdirRecurse(params.clonedRepoPath);
        }
    }

    return true;
}
