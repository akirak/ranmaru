val run_proxy :
     client_sockaddr:Eio.Net.Sockaddr.stream
  -> server_sockaddr:Eio.Net.Sockaddr.stream
  -> unit

val run_proxy_stdio :
  client_sockaddr:Eio.Net.Sockaddr.stream -> command:string list -> unit
