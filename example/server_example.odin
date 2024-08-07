package steamworks_example_server

import steam "../steamworks"
import "base:runtime"
import "core:c"
import "core:fmt"
import "core:mem"
import "core:strings"
import "core:time"

// https://partner.steamgames.com/doc/sdk/api
// https://partner.steamgames.com/doc/sdk/api#manual_dispatch


poll_group: steam.HSteamNetPollGroup
interface: ^steam.INetworkingSockets

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

    interface = steam.NetworkingSockets_SteamAPI()

    if interface == nil {
        panic("Failed to retrieve SteamNetworkingSockets")
    }

    util := steam.NetworkingUtils_SteamAPI()

    steam.NetworkingUtils_SetGlobalConfigValueInt32(util, .IP_AllowWithoutAuth, 1)

    steam.NetworkingUtils_SetDebugOutputFunction(util, .Everything, network_logging)

    addr: steam.SteamNetworkingIPAddr
    steam.SteamNetworkingIPAddr_Clear(&addr)

    addr.port = 25555

    opt: steam.SteamNetworkingConfigValue
    steam.SteamNetworkingConfigValue_t_SetPtr(&opt, .CallbacConnectionStatusChanged, cast(rawptr)connection_status_changed_cb)

    listen := steam.NetworkingSockets_CreateListenSocketIP(interface, &addr, 1, &opt)

    if listen == steam.HSteamListenSocket_Invalid {
        panic("Failed to create listening socket")
    }

    poll_group = steam.NetworkingSockets_CreatePollGroup(interface)

    if poll_group == steam.HSteamNetPollGroup_Invalid {
        panic("Failed to create poll group")
    }

    for {
        steam.NetworkingSockets_RunCallbacks(interface)

        message: ^steam.SteamNetworkingMessage

        message_count := steam.NetworkingSockets_ReceiveMessagesOnPollGroup(interface, poll_group, &message, 1)

        if (message_count < 0) {
            break
        }

        if (message_count > 0) {
            fmt.printf("%v\n", cstring(message.pData))
            steam.SteamNetworkingMessage_t_Release(message)
        }

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
        steam.NetworkingSockets_CloseConnection(interface, cb.hConn, 0, nil, false)

    case .Connecting:
        fmt.printf("Connection request from %v\n", cb.info.szConnectionDescription)

        if steam.NetworkingSockets_AcceptConnection(interface, cb.hConn) != .OK {
            steam.NetworkingSockets_CloseConnection(interface, cb.hConn, 0, nil, false)
            fmt.eprintln("Failed to accept connection")
            return
        }

        if !steam.NetworkingSockets_SetConnectionPollGroup(interface, cb.hConn, poll_group) {
            steam.NetworkingSockets_CloseConnection(interface, cb.hConn, 0, nil, false)
            fmt.eprintln("Failed to add to poll group")
            return
        }


    case .Connected:
    // We will get a callback immediately after accepting the connection.
    // Since we are the server, we can ignore this, it's not news to us.
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
