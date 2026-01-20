open Cmdliner

let to_unix path = `Unix path

let client_socket_path =
  let doc = "UNIX socket path to listen to" in
  let env = Cmd.Env.info "RANMARU_CLIENT_SOCKET" ~doc in
  Term.(
    const to_unix
    $ Arg.(
        required
        & opt (some string) None
        & info ["client"] ~env ~docv:"CLIENT" ~doc ) )

let server_socket_path =
  let doc = "UNIX socket path of the upstream server" in
  Term.(
    const Fun.id
    $ Arg.(
        value
        & opt (some non_dir_file) None
        & info ["master"] ~docv:"SERVER" ~doc ) )

let stdio_master =
  let doc = "Use stdio to communicate with the master server" in
  Term.(const Fun.id $ Arg.(value & flag & info ["stdio-master"] ~doc))

let master_command =
  let doc = "Command to start the master server" in
  Arg.(value & pos_all string [] & info [] ~docv:"COMMAND" ~doc)

let () =
  Printexc.record_backtrace true ;
  let doc =
    "LSP proxy that handles shutdown/exit and manages multiple clients"
  in
  let info = Cmd.info "ranmaru" ~doc in
  let resolve_server_sockaddr server_sockaddr =
    match server_sockaddr with
    | Some path -> Some (to_unix path)
    | None -> Sys.getenv_opt "RANMARU_MASTER_SOCKET" |> Option.map to_unix
  in
  let run client_sockaddr server_sockaddr_arg stdio_master command =
    let server_sockaddr_cli = Option.map to_unix server_sockaddr_arg in
    let server_sockaddr =
      if stdio_master then server_sockaddr_cli
      else resolve_server_sockaddr server_sockaddr_arg
    in
    match (stdio_master, server_sockaddr_cli, server_sockaddr, command) with
    | true, Some _, _, _ ->
        `Error (true, "Use either --master or --stdio-master, not both")
    | true, None, _, [] ->
        `Error (true, "Missing master COMMAND for --stdio-master")
    | true, None, _, command ->
        Ranmaru.run_proxy_stdio ~client_sockaddr ~command ;
        `Ok ()
    | false, _, Some server_sockaddr, [] ->
        Ranmaru.run_proxy ~client_sockaddr ~server_sockaddr ;
        `Ok ()
    | false, _, Some _, _ ->
        `Error (true, "Unexpected COMMAND without --stdio-master")
    | false, _, None, _ ->
        `Error (true, "Missing --master or --stdio-master configuration")
  in
  let cmd =
    Cmd.v info
      Term.(
        ret
          ( const run $ client_socket_path $ server_socket_path
          $ stdio_master $ master_command ) )
  in
  exit (Cmd.eval cmd)
