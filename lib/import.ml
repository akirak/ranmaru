module Client_registry = struct
  module Id = struct
    type t = int
  end

  type response_packet =
    [ `Response of Jsonrpc.Response.t
    | `Batch_response of Jsonrpc.Response.t list ]

  type t =
    { id_counter: Id.t Kcas.Loc.t
    ; stream_tbl: (Id.t, response_packet Eio.Stream.t) Kcas_data.Hashtbl.t }

  let make () =
    { id_counter= Kcas.Loc.make 0
    ; stream_tbl= Kcas_data.Hashtbl.create ~min_buckets:10 () }

  let delete {id_counter= _; stream_tbl} id =
    Kcas_data.Hashtbl.remove stream_tbl id

  let register {id_counter; stream_tbl} =
    let id = Kcas.Loc.fetch_and_add id_counter 1 in
    let stream = Eio.Stream.create 5 in
    Kcas_data.Hashtbl.add stream_tbl id stream ;
    (id, stream)

  let send {id_counter= _; stream_tbl} id packet =
    let stream = Kcas_data.Hashtbl.find stream_tbl id in
    Eio.Stream.add stream packet
end

module Id_translator = struct
  type t =
    { id_counter: int Kcas.Loc.t
    ; id_table: (int, Jsonrpc.Id.t) Kcas_data.Hashtbl.t }

  let make () =
    { id_counter= Kcas.Loc.make 0
    ; id_table= Kcas_data.Hashtbl.create ~min_buckets:20 () }

  let translate {id_counter; id_table} v =
    let new_id = Kcas.Loc.fetch_and_add id_counter 1 in
    Kcas_data.Hashtbl.add id_table new_id v ;
    `Int new_id

  let untranslate {id_table; id_counter= _} = function
    | `Int k ->
        let v = Kcas_data.Hashtbl.find id_table k in
        Kcas_data.Hashtbl.remove id_table k ;
        v
    | _ -> failwith "Only int ids are supported"
end

module Client_map = struct
  type t = {tbl: (Jsonrpc.Id.t, Client_registry.Id.t) Kcas_data.Hashtbl.t}

  let make () = {tbl= Kcas_data.Hashtbl.create ~min_buckets:50 ()}

  let add {tbl} client_id req_id = Kcas_data.Hashtbl.add tbl req_id client_id

  let take {tbl} req_id =
    let result = Kcas_data.Hashtbl.find tbl req_id in
    Kcas_data.Hashtbl.remove tbl req_id ;
    result

  let take_opt {tbl} req_id =
    Kcas_data.Hashtbl.find_opt tbl req_id
    |> Option.map (fun result ->
        Kcas_data.Hashtbl.remove tbl req_id ;
        result )
end

module Initializer = struct
  type t =
    { mutex: Eio.Mutex.t
    ; init_done: Eio.Condition.t
    ; requested: bool Kcas.Loc.t
    ; last_params_loc: Lsp.Types.InitializeParams.t option Kcas.Loc.t
    ; result_loc:
        (Jsonrpc.Json.t, Jsonrpc.Response.Error.t) Result.t option Kcas.Loc.t
    }

  let make () =
    { mutex= Eio.Mutex.create ()
    ; init_done= Eio.Condition.create ()
    ; requested= Kcas.Loc.make false
    ; last_params_loc= Kcas.Loc.make None
    ; result_loc= Kcas.Loc.make None }

  let set {mutex= _; init_done; requested= _; last_params_loc= _; result_loc}
      result =
    Kcas.Loc.set result_loc (Some result) ;
    Eio.Condition.broadcast init_done

  let thisClientInfo =
    Lsp.Types.InitializeParams.create_clientInfo ~name:"ranmaru" ~version:"0"
      ()

  let augment_params params =
    (* TODO: Add an option to set the PID *)
    (* let pid = Unix.getpid () in *)
    let open Lsp.Types.InitializeParams in
    {params with clientInfo= Some thisClientInfo; processId= None}

  let to_jsonrpc_params params =
    Lsp.Types.InitializeParams.yojson_of_t params
    |> Jsonrpc.Structured.t_of_yojson

  let await ~server_socket ~id ~params
      {mutex; init_done; requested; last_params_loc; result_loc} =
    Eio.Mutex.use_rw ~protect:true mutex
    @@ fun () ->
    match Kcas.Loc.get result_loc with
    | Some result -> result
    | None ->
        ( if Kcas.Loc.get requested then ()
          else
            let custom_params = augment_params params in
            Kcas.Loc.set requested true ;
            Kcas.Loc.set last_params_loc (Some custom_params) ;
            let request =
              Jsonrpc.Request.create
                ~params:(to_jsonrpc_params custom_params)
                ~id ~method_:"initialize" ()
            in
            Lsp_utils.write_packet server_socket
              (Jsonrpc.Packet.Request request) ) ;
        while Option.is_none (Kcas.Loc.get result_loc) do
          Eio.Condition.await init_done mutex
        done ;
        Option.get (Kcas.Loc.get result_loc)
end
