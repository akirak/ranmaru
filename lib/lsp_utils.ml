let crlf_split = Str.regexp "\r\n"

exception Lsp_header_parse_error of string

module Header = struct
  type t = {content_length: int option}

  let lookup_opt key alist =
    match
      List.find_opt
        (fun (k, _) -> String.lowercase_ascii k = String.lowercase_ascii key)
        alist
    with
    | Some (_, v) -> Some v
    | None -> None

  let parse_header_line line =
    let index = Str.search_forward (Str.regexp ":") line 0 in
    let key = Str.string_before line index in
    let value = Str.string_after line (index + 1) in
    (key, String.trim value)

  let parse_message string =
    let rec loop headers n =
      match Str.search_forward crlf_split string n with
      | index when index = n -> (headers, Str.string_after string (n + 2))
      | index ->
          let line = String.sub string n (index - n) in
          loop (parse_header_line line :: headers) (index + 2)
    in
    let fields, body = loop [] 0 in
    let content_type = lookup_opt "content-type" fields in
    let content_length =
      match
        lookup_opt "content-length" fields |> Option.map int_of_string_opt
      with
      | Some (Some length) -> Some length
      | None -> None
      | Some None ->
          raise (Lsp_header_parse_error "invalid content-length value")
    in
    if Option.is_some content_length || Option.is_some content_type then
      ({content_length}, body)
    else raise (Lsp_header_parse_error "empty header")
end

type message = Raw of Cstruct.t | Decoded of Jsonrpc.Packet.t

let to_packet = function
  | `Request req -> Jsonrpc.Packet.Request req
  | `Notification notification -> Jsonrpc.Packet.Notification notification

let write_packet flow packet =
  let json = Jsonrpc.Packet.yojson_of_t packet in
  let json_str = Yojson.Safe.to_string json in
  let content_length = String.length json_str in
  (* This function is only used for building the response to a shutdown
     request. With a CRLF appended to the entire message, Emacs lsp/eglot
     booster will fail, so we don't append it. *)
  let lsp_message =
    Printf.sprintf "Content-Length: %d\r\n\r\n%s" content_length json_str
  in
  Eio.Flow.copy_string lsp_message flow

module Reader = struct
  let get_next_input flow =
    let buffer = Cstruct.create 4096 in
    match Eio.Flow.single_read flow buffer with
    | bytes_read when bytes_read > 0 ->
        Some (Cstruct.sub buffer 0 bytes_read |> Cstruct.to_string)
    | _ -> None

  type state =
    | Partial of (Header.t option * string option)
    | Complete of (Jsonrpc.Packet.t * string option)

  let parse_packet body =
    Yojson.Safe.from_string body |> Jsonrpc.Packet.t_of_yojson

  let try_parse_header prev_input string =
    let full_string =
      match prev_input with
      | Some prev_string -> prev_string ^ string
      | None -> string
    in
    match Header.parse_message full_string with
    | header, body -> (
      match header.content_length with
      | _ when String.length body = 0 -> Partial (Some header, None)
      | None -> Complete (parse_packet body, None)
      | Some length when String.length body < length ->
          Partial (Some header, Some body)
      | Some length when String.length body = length ->
          Complete (parse_packet body, None)
      | Some length ->
          Complete
            ( parse_packet (Str.string_before body length)
            , Some (Str.string_after body length) ) )

  let rec loop1 ?on_eof flow opt_header opt_string =
    let open Header in
    match get_next_input flow with
    | None -> (
      match on_eof with
      | Some handle ->
          handle () ;
          loop1 ?on_eof flow opt_header opt_string
      | None ->
          Eio.Fiber.yield () ;
          loop1 ?on_eof flow opt_header opt_string )
    | Some string -> (
      match opt_header with
      | None -> (
        match try_parse_header opt_string string with
        | Partial (header, body) ->
            Eio.Fiber.yield () ;
            loop1 ?on_eof flow header body
        | Complete (packet, rest) -> (packet, rest) )
      | Some {content_length= None} -> (parse_packet string, None)
      | Some {content_length= Some length} when String.length string < length
        ->
          Eio.Fiber.yield () ;
          loop1 ?on_eof flow opt_header (Some string)
      | Some {content_length= Some length} when String.length string = length
        ->
          (parse_packet string, None)
      | Some {content_length= Some length} ->
          ( parse_packet (Str.string_before string length)
          , Some (Str.string_after string length) ) )

  let to_stream stream flow =
    let rec loop opt_string =
      let packet, rest = loop1 flow None opt_string in
      Eio.Stream.add stream packet ;
      Eio.Fiber.yield () ;
      loop rest
    in
    loop None

  let to_stream_with_eof ~on_eof stream flow =
    let rec loop opt_string =
      let packet, rest = loop1 ~on_eof flow None opt_string in
      Eio.Stream.add stream packet ;
      Eio.Fiber.yield () ;
      loop rest
    in
    loop None
end
