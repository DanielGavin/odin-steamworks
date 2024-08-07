package steamworks_example_client

import steam "../steamworks"
import "base:runtime"
import "core:c"
import "core:fmt"
import "core:mem"
import "core:strings"
import "core:time"

// https://partner.steamgames.com/doc/sdk/api
// https://partner.steamgames.com/doc/sdk/api#manual_dispatch


main :: proc() {
    if steam.RestartAppIfNecessary(steam.uAppIdInvalid) {
        fmt.println("Launching app through steam...")
        return
    }

    if !steam.Init() do panic("steam.Init failed. Make sure Steam is running.")

    steam.Client_SetWarningMessageHook(steam.Client(), steam_debug_text_hook)

    if !steam.User_BLoggedOn(steam.User()) {
        panic("User isn't logged in.")
    } else {
        fmt.println("USER IS LOGGED IN")
    }

    interface := steam.NetworkingSockets_SteamAPI()

    if interface == nil {
        panic("Failed to retrieve SteamNetworkingSockets")
    }

    util := steam.NetworkingUtils_SteamAPI()

    steam.NetworkingUtils_SetGlobalConfigValueInt32(util, .IP_AllowWithoutAuth, 1)

    steam.NetworkingUtils_SetDebugOutputFunction(util, .Everything, network_logging)

    addr: steam.SteamNetworkingIPAddr
    steam.SteamNetworkingIPAddr_ParseString(&addr, "127.0.0.1:25555")

    opt: steam.SteamNetworkingConfigValue
    steam.SteamNetworkingConfigValue_t_SetPtr(&opt, .CallbacConnectionStatusChanged, cast(rawptr)connection_status_changed_cb)

    connection := steam.NetworkingSockets_ConnectByIPAddress(interface, &addr, 1, &opt)

    if connection == steam.HSteamNetConnection_Invalid {
        panic("Failed to create connection to server")
    }

    for {
        msg := "Hellope!"
        steam.NetworkingSockets_SendMessageToConnection(interface, connection, raw_data(msg), u32(len(msg)), steam.nSteamNetworkingSend_Reliable, nil)
        steam.NetworkingSockets_RunCallbacks(interface)
        time.sleep(500 * time.Millisecond)
    }


    steam.Shutdown()
}

connection_status_changed_cb :: proc "c" (cb: ^steam.SteamNetConnectionStatusChangedCallback) {
    context = runtime.default_context()

    // What's the state of the connection?
    #partial switch (cb.info.eState) 
    {
    case .None:
    // NOTE: We will get callbacks here when we destroy connections.  You can ignore these.

    case .ProblemDetectedLocally, .ClosedByPeer:
        // Print an appropriate message
        if (cb.eOldState == .Connecting) {
            // Note: we could distinguish between a timeout, a rejected connection,
            // or some other transport problem.
            fmt.eprintf("We sought the remote host, yet our efforts were met with defeat.  (%v)", cb.info.szEndDebug)
        } else if (cb.info.eState == .ProblemDetectedLocally) {
            fmt.eprintf("Alas, troubles beset us; we have lost contact with the host.  (%v)", cb.info.szEndDebug)
        }
    // Clean up the connection.  This is important!
    // The connection is "closed" in the network sense, but
    // it has not been destroyed.  We must close it on our end, too
    // to finish up.  The reason information do not matter in this case,
    // and we cannot linger because it's already closed on the other end,
    // so we just pass 0's.
    case .Connecting:
        fmt.eprintln("Connecting")

    case .Connected:
        fmt.eprintln("Connected!")
    }
}

network_logging :: proc "c" (type: steam.ESteamNetworkingSocketsDebugOutputType, text: cstring) {
    context = runtime.default_context()
    fmt.printfln("%v", text)
}


steam_debug_text_hook :: proc "c" (severity: c.int, debugText: cstring) {
    // if you're running in the debugger, only warnings (nSeverity >= 1) will be sent
    // if you add -debug_steamworksapi to the command-line, a lot of extra informational messages will also be sent
    runtime.print_string(string(debugText))

    if severity >= 1 {
        runtime.debug_trap()
    }
}
