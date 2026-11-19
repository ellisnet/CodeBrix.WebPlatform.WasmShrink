using System;

namespace CodeBrix.WebPlatform.WasmShrink;

/// <summary>
/// Thrown when the wasm-opt program cannot be found for the current machine, cannot be
/// started, or reports a failure while shrinking a WebAssembly file.
/// </summary>
public class WasmShrinkException : Exception
{
    /// <summary>Creates the exception with a message that says what went wrong and what to do about it.</summary>
    /// <param name="message">The explanation shown to the developer.</param>
    public WasmShrinkException(string message)
        : base(message)
    {
    }

    /// <summary>Creates the exception with a message and the lower-level error that caused it.</summary>
    /// <param name="message">The explanation shown to the developer.</param>
    /// <param name="innerException">The error raised by the operating system or the runtime.</param>
    public WasmShrinkException(string message, Exception innerException)
        : base(message, innerException)
    {
    }
}
