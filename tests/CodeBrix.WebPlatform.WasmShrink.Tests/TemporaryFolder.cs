using System;
using System.IO;

namespace CodeBrix.WebPlatform.WasmShrink.Tests;

/// <summary>A folder under the system's temporary folder that is deleted when the test ends.</summary>
internal sealed class TemporaryFolder : IDisposable
{
    public TemporaryFolder()
    {
        Path = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "codebrix-wasmshrink-tests-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(Path);
    }

    public string Path { get; }

    public string File(string name) => System.IO.Path.Combine(Path, name);

    public void Dispose()
    {
        try
        {
            Directory.Delete(Path, recursive: true);
        }
        catch (IOException)
        {
            // Left behind for the operating system's own temporary-folder cleanup.
        }
    }
}
