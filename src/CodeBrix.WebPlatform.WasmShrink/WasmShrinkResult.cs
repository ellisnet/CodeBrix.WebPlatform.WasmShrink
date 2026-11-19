namespace CodeBrix.WebPlatform.WasmShrink;

/// <summary>What one run of the wasm-opt program produced.</summary>
public class WasmShrinkResult
{
    /// <summary>Creates a result from the values the finished process reported.</summary>
    /// <param name="exitCode">The exit code of the process; zero means success.</param>
    /// <param name="standardOutput">Everything the process wrote to standard output.</param>
    /// <param name="standardError">Everything the process wrote to standard error.</param>
    public WasmShrinkResult(int exitCode, string standardOutput, string standardError)
    {
        ExitCode = exitCode;
        StandardOutput = standardOutput ?? string.Empty;
        StandardError = standardError ?? string.Empty;
    }

    /// <summary>The exit code of the process; zero means success.</summary>
    public int ExitCode { get; }

    /// <summary>Everything the process wrote to standard output.</summary>
    public string StandardOutput { get; }

    /// <summary>Everything the process wrote to standard error; wasm-opt reports its errors here.</summary>
    public string StandardError { get; }

    /// <summary><c>true</c> when the process exited with code zero.</summary>
    public bool Succeeded => ExitCode == 0;
}
