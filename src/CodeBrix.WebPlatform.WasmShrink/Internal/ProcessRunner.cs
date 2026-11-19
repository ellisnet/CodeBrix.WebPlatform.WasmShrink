using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.Threading;
using System.Threading.Tasks;

namespace CodeBrix.WebPlatform.WasmShrink.Internal;

/// <summary>Starts a program, waits for it, and collects what it wrote.</summary>
internal static class ProcessRunner
{
    /// <summary>
    /// Runs <paramref name="executablePath"/> with <paramref name="arguments"/> and returns its
    /// exit code and output. Cancelling stops the program.
    /// </summary>
    internal static async Task<WasmShrinkResult> RunAsync(
        string executablePath,
        IEnumerable<string> arguments,
        string workingDirectory,
        CancellationToken cancellationToken)
    {
        var startInfo = new ProcessStartInfo
        {
            FileName = executablePath,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            RedirectStandardInput = true,
            UseShellExecute = false,
            CreateNoWindow = true,
        };

        if (!string.IsNullOrEmpty(workingDirectory))
        {
            startInfo.WorkingDirectory = workingDirectory;
        }

        foreach (var argument in arguments)
        {
            startInfo.ArgumentList.Add(argument);
        }

        using var process = new Process { StartInfo = startInfo };

        try
        {
            process.Start();
        }
        catch (Win32Exception exception)
        {
            throw new WasmShrinkException($"'{executablePath}' could not be started: {exception.Message}", exception);
        }

        process.StandardInput.Close();
        var standardOutput = process.StandardOutput.ReadToEndAsync(CancellationToken.None);
        var standardError = process.StandardError.ReadToEndAsync(CancellationToken.None);

        try
        {
            await process.WaitForExitAsync(cancellationToken).ConfigureAwait(false);
        }
        catch (OperationCanceledException)
        {
            Stop(process);
            throw;
        }

        return new WasmShrinkResult(
            process.ExitCode,
            await standardOutput.ConfigureAwait(false),
            await standardError.ConfigureAwait(false));
    }

    private static void Stop(Process process)
    {
        try
        {
            if (!process.HasExited)
            {
                process.Kill(entireProcessTree: true);
            }
        }
        catch (Exception exception) when (exception is InvalidOperationException or Win32Exception)
        {
            // The program ended on its own between the check and the request to stop it.
        }
    }
}
