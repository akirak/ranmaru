open Cmdliner

let starts_with s prefix =
  let s_len = String.length s in
  let prefix_len = String.length prefix in
  s_len >= prefix_len && String.sub s 0 prefix_len = prefix

let lsp_message_of_packet packet =
  let json = Jsonrpc.Packet.yojson_of_t packet |> Yojson.Safe.to_string in
  Printf.sprintf "Content-Length: %d\r\n\r\n%s" (String.length json) json

let write_all fd payload =
  let rec loop offset =
    if offset < String.length payload then
      let written =
        Unix.write_substring fd payload offset
          (String.length payload - offset)
      in
      loop (offset + written)
  in
  loop 0

let send_packet fd packet = lsp_message_of_packet packet |> write_all fd

module Packet_reader = struct
  type t = {fd: Unix.file_descr; mutable buffer: string}

  let create fd = {fd; buffer= ""}

  let find_header_end s =
    let rec loop idx =
      if idx + 3 >= String.length s then None
      else if
        s.[idx] = '\r' && s.[idx + 1] = '\n' && s.[idx + 2] = '\r'
        && s.[idx + 3] = '\n'
      then Some idx
      else loop (idx + 1)
    in
    loop 0

  let parse_content_length header =
    let lines = String.split_on_char '\n' header in
    let rec loop = function
      | [] -> failwith "Missing Content-Length header"
      | line :: rest ->
          let trimmed = String.trim line in
          let lower = String.lowercase_ascii trimmed in
          if starts_with lower "content-length:" then
            let value =
              String.sub trimmed 15 (String.length trimmed - 15)
              |> String.trim
            in
            int_of_string value
          else loop rest
    in
    loop lines

  let read_more t =
    let bytes = Bytes.create 4096 in
    match Unix.read t.fd bytes 0 4096 with
    | 0 -> failwith "Unexpected EOF while reading LSP packet"
    | n ->
        let chunk = Bytes.sub_string bytes 0 n in
        t.buffer <- t.buffer ^ chunk

  let rec read_packet t =
    match find_header_end t.buffer with
    | None ->
        read_more t ;
        read_packet t
    | Some header_end ->
        let header = String.sub t.buffer 0 header_end in
        let rest =
          String.sub t.buffer (header_end + 4)
            (String.length t.buffer - header_end - 4)
        in
        let content_length = parse_content_length header in
        t.buffer <- rest ;
        let rec ensure_body () =
          if String.length t.buffer >= content_length then ()
          else (
            read_more t ;
            ensure_body () )
        in
        ensure_body () ;
        let packet_body = String.sub t.buffer 0 content_length in
        let leftover =
          String.sub t.buffer content_length
            (String.length t.buffer - content_length)
        in
        t.buffer <- leftover ;
        Yojson.Safe.from_string packet_body |> Jsonrpc.Packet.t_of_yojson

  let read_packet_with_timeout t timeout =
    if t.buffer <> "" then Some (read_packet t)
    else
      let readable, _, _ = Unix.select [t.fd] [] [] timeout in
      if readable = [] then None else Some (read_packet t)
end

let temp_socket_path suffix =
  let path = Filename.temp_file "ranmaru_test_" suffix in
  Unix.unlink path ;
  path

let connect_with_retry path =
  let rec loop attempts =
    let fd = Unix.socket Unix.PF_UNIX Unix.SOCK_STREAM 0 in
    try
      Unix.connect fd (Unix.ADDR_UNIX path) ;
      fd
    with exn ->
      Unix.close fd ;
      if attempts <= 0 then raise exn
      else (
        Unix.sleepf 0.05 ;
        loop (attempts - 1) )
  in
  loop 50

let packet_to_string packet =
  Jsonrpc.Packet.yojson_of_t packet |> Yojson.Safe.to_string

let test_cmdline_parsing () =
  (* Test that the command accepts --client and --master options *)
  let argv =
    [| "ranmaru"
     ; "--client"
     ; "/tmp/client.sock"
     ; "--master"
     ; "/tmp/master.sock" |]
  in
  (* Create a simple test command that extracts the arguments *)
  let test_client_path = ref None in
  let test_master_path = ref None in
  let client_socket_path =
    let doc = "UNIX socket path to listen to" in
    let env = Cmd.Env.info "RANMARU_CLIENT_SOCKET" ~doc in
    Term.(
      const (fun path ->
          test_client_path := Some path ;
          `Unix path )
      $ Arg.(
          required
          & opt (some string) None
          & info ["client"] ~env ~docv:"CLIENT" ~doc ) )
  in
  let server_socket_path =
    let doc = "UNIX socket path of the upstream server" in
    let env = Cmd.Env.info "RANMARU_MASTER_SOCKET" ~doc in
    Term.(
      const (fun path ->
          test_master_path := Some path ;
          `Unix path )
      $ Arg.(
          required
          & opt (some string) None
          & info ["master"] ~env ~docv:"SERVER" ~doc ) )
  in
  let test_term =
    Term.(const (fun _ _ -> `Ok ()) $ client_socket_path $ server_socket_path)
  in
  let info = Cmd.info "ranmaru" ~doc:"test" in
  let cmd = Cmd.v info test_term in
  (* Parse the command line *)
  match Cmd.eval_value ~argv cmd with
  | Ok (`Ok _) ->
      Alcotest.(check (option string))
        "client path" (Some "/tmp/client.sock") !test_client_path ;
      Alcotest.(check (option string))
        "master path" (Some "/tmp/master.sock") !test_master_path
  | _ -> Alcotest.fail "Command line parsing failed"

let test_env_vars () =
  (* Test that environment variables work *)
  Unix.putenv "RANMARU_CLIENT_SOCKET" "/env/client.sock" ;
  Unix.putenv "RANMARU_MASTER_SOCKET" "/env/master.sock" ;
  let argv = [|"ranmaru"|] in
  let test_client_path = ref None in
  let test_master_path = ref None in
  let client_socket_path =
    let doc = "UNIX socket path to listen to" in
    let env = Cmd.Env.info "RANMARU_CLIENT_SOCKET" ~doc in
    Term.(
      const (fun path ->
          test_client_path := Some path ;
          `Unix path )
      $ Arg.(
          required
          & opt (some string) None
          & info ["client"] ~env ~docv:"CLIENT" ~doc ) )
  in
  let server_socket_path =
    let doc = "UNIX socket path of the upstream server" in
    let env = Cmd.Env.info "RANMARU_MASTER_SOCKET" ~doc in
    Term.(
      const (fun path ->
          test_master_path := Some path ;
          `Unix path )
      $ Arg.(
          required
          & opt (some string) None
          & info ["master"] ~env ~docv:"SERVER" ~doc ) )
  in
  let test_term =
    Term.(const (fun _ _ -> `Ok ()) $ client_socket_path $ server_socket_path)
  in
  let info = Cmd.info "ranmaru" ~doc:"test" in
  let cmd = Cmd.v info test_term in
  match Cmd.eval_value ~argv cmd with
  | Ok (`Ok _) ->
      Alcotest.(check (option string))
        "client env path" (Some "/env/client.sock") !test_client_path ;
      Alcotest.(check (option string))
        "master env path" (Some "/env/master.sock") !test_master_path
  | _ -> Alcotest.fail "Environment variable test failed"

let test_run_proxy_sequence () =
  let client_path = temp_socket_path "client.sock" in
  let master_path = temp_socket_path "master.sock" in
  let server_fd = Unix.socket Unix.PF_UNIX Unix.SOCK_STREAM 0 in
  let client_fd = ref None in
  let master_conn = ref None in
  Unix.bind server_fd (Unix.ADDR_UNIX master_path) ;
  Unix.listen server_fd 1 ;
  let pid = Unix.fork () in
  if pid = 0 then (
    Ranmaru.run_proxy ~client_sockaddr:(`Unix client_path)
      ~server_sockaddr:(`Unix master_path) ;
    exit 0 )
  else
    let cleanup () =
      (match !client_fd with
      | None -> ()
      | Some fd -> Unix.close fd) ;
      (match !master_conn with
      | None -> ()
      | Some fd -> Unix.close fd) ;
      (try Unix.close server_fd with _ -> ()) ;
      (try Unix.kill pid Sys.sigterm with _ -> ()) ;
      (try ignore (Unix.waitpid [] pid) with _ -> ()) ;
      (try if Sys.file_exists master_path then Unix.unlink master_path with _ ->
         ()) ;
      try if Sys.file_exists client_path then Unix.unlink client_path with _ ->
          ()
    in
    Fun.protect ~finally:cleanup (fun () ->
        let client = connect_with_retry client_path in
        client_fd := Some client ;
        let client_reader = Packet_reader.create client in
        let master_fd, _ = Unix.accept server_fd in
        master_conn := Some master_fd ;
        let master_reader = Packet_reader.create master_fd in
        let req_id = `Int 99 in
        let req = Jsonrpc.Request.create ~id:req_id ~method_:"test" () in
        send_packet client (Jsonrpc.Packet.Request req) ;
        let forwarded_request =
          match Packet_reader.read_packet master_reader with
          | Jsonrpc.Packet.Request request -> request
          | packet ->
              Alcotest.failf "Expected a request, got %s"
                (packet_to_string packet)
        in
        Alcotest.(check string)
          "forwarded method" "test" forwarded_request.method_ ;
        Alcotest.(check bool)
          "request id translated" true (forwarded_request.id <> req_id) ;
        let response = Jsonrpc.Response.ok forwarded_request.id `Null in
        send_packet master_fd (Jsonrpc.Packet.Response response) ;
        ( match Packet_reader.read_packet client_reader with
        | Jsonrpc.Packet.Response response ->
            Alcotest.(check bool)
              "response id restored" true (response.id = req_id)
        | packet ->
            Alcotest.failf "Expected a response, got %s"
              (packet_to_string packet) ) ;
        let shutdown_id = `Int 1 in
        let shutdown =
          Jsonrpc.Request.create ~id:shutdown_id ~method_:"shutdown" ()
        in
        send_packet client (Jsonrpc.Packet.Request shutdown) ;
        ( match Packet_reader.read_packet client_reader with
        | Jsonrpc.Packet.Response response ->
            Alcotest.(check bool)
              "shutdown response id" true (response.id = shutdown_id) ;
            Alcotest.(check bool)
              "shutdown response payload" true (response.result = Ok `Null)
        | packet ->
            Alcotest.failf "Expected a shutdown response, got %s"
              (packet_to_string packet) ) ;
        ( match Packet_reader.read_packet_with_timeout master_reader 0.2 with
        | None -> ()
        | Some packet ->
            Alcotest.failf "Shutdown forwarded to master: %s"
              (packet_to_string packet) ) ;
        let exit_notification =
          Jsonrpc.Notification.create ~method_:"exit" ()
        in
        send_packet client
          (Jsonrpc.Packet.Notification exit_notification) ;
        ( match Packet_reader.read_packet_with_timeout master_reader 0.2 with
        | None -> ()
        | Some packet ->
            Alcotest.failf "Exit forwarded to master: %s"
              (packet_to_string packet) ) ;
        Unix.close client ;
        client_fd := None ;
        let client2 = connect_with_retry client_path in
        client_fd := Some client2 ;
        let client2_reader = Packet_reader.create client2 in
        let req2_id = `Int 7 in
        let req2 =
          Jsonrpc.Request.create ~id:req2_id ~method_:"after-exit" ()
        in
        send_packet client2 (Jsonrpc.Packet.Request req2) ;
        let forwarded_request2 =
          match Packet_reader.read_packet master_reader with
          | Jsonrpc.Packet.Request request -> request
          | packet ->
              Alcotest.failf "Expected a request, got %s"
                (packet_to_string packet)
        in
        Alcotest.(check string)
          "forwarded method after exit" "after-exit"
          forwarded_request2.method_ ;
        let response2 = Jsonrpc.Response.ok forwarded_request2.id `Null in
        send_packet master_fd (Jsonrpc.Packet.Response response2) ;
        match Packet_reader.read_packet client2_reader with
        | Jsonrpc.Packet.Response response ->
            Alcotest.(check bool)
              "response id restored after exit" true (response.id = req2_id)
        | packet ->
            Alcotest.failf "Expected a response, got %s"
              (packet_to_string packet) )

let () =
  let open Alcotest in
  run "Ranmaru Command Line"
    [ ( "cmdline"
      , [ test_case "Command line parsing" `Quick test_cmdline_parsing
        ; test_case "Environment variables" `Quick test_env_vars ] )
    ; ("proxy", [test_case "run_proxy sequence" `Quick test_run_proxy_sequence])
    ]
