// Copyright (c) 2009-2010 Satoshi Nakamoto
// Copyright (c) 2009-2020 The Bitcoin Core developers
// Distributed under the MIT software license, see the accompanying
// file COPYING or http://www.opensource.org/licenses/mit-license.php.

#if defined(HAVE_CONFIG_H)
#include <config/bitcoin-config.h>
#endif

#include <chainparams.h>
#include <clientversion.h>
#include <compat.h>
#include <init.h>
#include <interfaces/chain.h>
#include <node/context.h>
#include <node/ui_interface.h>
#include <noui.h>
#include <shutdown.h>
#include <util/ref.h>
#include <util/strencodings.h>
#include <util/system.h>
#include <util/threadnames.h>
#include <util/translation.h>
#include <util/url.h>

#include <functional>

const std::function<std::string(const char*)> G_TRANSLATION_FUN = nullptr;
UrlDecodeFn* const URL_DECODE = urlDecode;

static void WaitForShutdown(NodeContext& node)
{
    while (!ShutdownRequested())
    {
        UninterruptibleSleep(std::chrono::milliseconds{200});
    }
    Interrupt(node);
}

static bool AppInit(int argc, char* argv[])
{
    NodeContext node;

    bool fRet = false;

    util::ThreadSetInternalName("init");

    // If Qt is used, parameters/bitcoin.conf are parsed in qt/bitcoin.cpp's main()
    SetupServerArgs(node);
    ArgsManager& args = *Assert(node.args);
    std::string error;
    if (!args.ParseParameters(argc, argv, error)) {
        return InitError(Untranslated(strprintf("Error parsing command line arguments: %s\n", error)));
    }

    // Process help and version before taking care about datadir
    if (HelpRequested(args) || args.IsArgSet("-version")) {
        std::string strUsage = PACKAGE_NAME " version " + FormatFullVersion() + "\n";

        if (args.IsArgSet("-version")) {
            strUsage += FormatParagraph(LicenseInfo()) + "\n";
        } else {
            strUsage += "\nUsage:  rincoind [options]                     Start " PACKAGE_NAME "\n";
            strUsage += "\n" + args.GetHelpMessage();
        }

        tfm::format(std::cout, "%s", strUsage);
        return true;
    }

    util::Ref context{node};
    try
    {
        if (!CheckDataDirOption()) {
            return InitError(Untranslated(strprintf("Specified data directory \"%s\" does not exist.\n", args.GetArg("-datadir", ""))));
        }
        if (!args.ReadConfigFiles(error, true)) {
            return InitError(Untranslated(strprintf("Error reading configuration file: %s\n", error)));
        }

        // rincoin-sim: Mainnet and Testnet are disabled at the daemon level.
        // This build is configured for regtest simulation only.
        // (bitcoin-cli/bitcoin-tx/bitcoin-wallet can still load MainParams
        //  in offline read-only contexts; only the node daemon is restricted.)
        const std::string& chain_name = args.GetChainName();
        if (chain_name == CBaseChainParams::MAIN) {
            return InitError(Untranslated(
                "Mainnet is disabled in rincoin-sim. Use -regtest only.\n"));
        }
        if (chain_name == CBaseChainParams::TESTNET) {
            return InitError(Untranslated(
                "Testnet is disabled in rincoin-sim. This repo uses 1/1000 "
                "scaled params incompatible with public Testnet consensus. "
                "Use -regtest only.\n"));
        }

        // Check for chain settings (Params() calls are only valid after this clause)
        try {
            SelectParams(args.GetChainName());
        } catch (const std::exception& e) {
            return InitError(Untranslated(strprintf("%s\n", e.what())));
        }

        // Error out when loose non-argument tokens are encountered on command line
        for (int i = 1; i < argc; i++) {
            if (!IsSwitchChar(argv[i][0])) {
                return InitError(Untranslated(strprintf("Command line contains unexpected token '%s', see rincoind -h for a list of options.\n", argv[i])));
            }
        }

        if (!args.InitSettings(error)) {
            InitError(Untranslated(error));
            return false;
        }

        // -server defaults to true for bitcoind but not for the GUI so do this here
        args.SoftSetBoolArg("-server", true);
        // Set this early so that parameter interactions go to console
        InitLogging(args);
        InitParameterInteraction(args);
        if (!AppInitBasicSetup(args)) {
            // InitError will have been called with detailed error, which ends up on console
            return false;
        }
        if (!AppInitParameterInteraction(args)) {
            // InitError will have been called with detailed error, which ends up on console
            return false;
        }
        if (!AppInitSanityChecks())
        {
            // InitError will have been called with detailed error, which ends up on console
            return false;
        }
        if (args.GetBoolArg("-daemon", false)) {
#if HAVE_DECL_DAEMON
#if defined(MAC_OSX)
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
#endif
            tfm::format(std::cout, PACKAGE_NAME " starting\n");

            // Daemonize
            if (daemon(1, 0)) { // don't chdir (1), do close FDs (0)
                return InitError(Untranslated(strprintf("daemon() failed: %s\n", strerror(errno))));
            }
#if defined(MAC_OSX)
#pragma GCC diagnostic pop
#endif
#else
            return InitError(Untranslated("-daemon is not supported on this operating system\n"));
#endif // HAVE_DECL_DAEMON
        }
        // Lock data directory after daemonization
        if (!AppInitLockDataDirectory())
        {
            // If locking the data directory failed, exit immediately
            return false;
        }
        fRet = AppInitInterfaces(node) && AppInitMain(context, node);
    }
    catch (const std::exception& e) {
        PrintExceptionContinue(&e, "AppInit()");
    } catch (...) {
        PrintExceptionContinue(nullptr, "AppInit()");
    }

    if (!fRet)
    {
        Interrupt(node);
    } else {
        WaitForShutdown(node);
    }
    Shutdown(node);

    return fRet;
}

int main(int argc, char* argv[])
{
#ifdef WIN32
    util::WinCmdLineArgs winArgs;
    std::tie(argc, argv) = winArgs.get();
#endif
    SetupEnvironment();

    // Connect bitcoind signal handlers
    noui_connect();

    return (AppInit(argc, argv) ? EXIT_SUCCESS : EXIT_FAILURE);
}
