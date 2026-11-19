using System;
using System.Collections.Generic;

namespace CodeBrix.WebPlatform.WasmShrink.Internal;

/// <summary>Turns a <see cref="WasmShrinkOptions"/> into the wasm-opt command line.</summary>
internal static class ArgumentBuilder
{
    /// <summary>The wasm-opt switch for an optimization level, for example <c>-Oz</c>.</summary>
    internal static string LevelSwitch(WasmShrinkLevel level)
        => level switch
        {
            WasmShrinkLevel.O0 => "-O0",
            WasmShrinkLevel.O1 => "-O1",
            WasmShrinkLevel.O2 => "-O2",
            WasmShrinkLevel.O3 => "-O3",
            WasmShrinkLevel.O4 => "-O4",
            WasmShrinkLevel.Os => "-Os",
            WasmShrinkLevel.Oz => "-Oz",
            _ => throw new ArgumentOutOfRangeException(nameof(level), level, "Unknown optimization level."),
        };

    /// <summary>The full argument list for shrinking <paramref name="inputPath"/> into <paramref name="outputPath"/>.</summary>
    internal static List<string> Build(string inputPath, string outputPath, WasmShrinkOptions options)
    {
        var arguments = new List<string>
        {
            inputPath,
            LevelSwitch(options.Level),
            options.KeepDebugInfo ? "--debuginfo" : "--strip-debug",
        };

        foreach (var extra in options.AdditionalArguments)
        {
            if (string.IsNullOrWhiteSpace(extra))
            {
                throw new ArgumentException("An additional argument is empty.", nameof(options));
            }

            arguments.Add(extra);
        }

        arguments.Add("-o");
        arguments.Add(outputPath);
        return arguments;
    }
}
