using System;
using System.Threading;
using MegaCrit.Sts2.Core.Logging;
using MegaCrit.Sts2.Core.Modding;

namespace Sts2ModMaster.NativeLoaderProbe;

[ModInitializer(nameof(Initialize))]
public static class LoaderProbe
{
    private static int _invocations;

    public static void Initialize()
    {
        if (Interlocked.Increment(ref _invocations) != 1)
        {
            throw new InvalidOperationException("Native loader probe initializer was invoked more than once.");
        }

        Log.Info("STS2_MOD_MASTER_NATIVE_LOADER_PROBE/0.1.0 INITIALIZED count=1", 2);
    }
}
