class Server {
  int? id;
  String name;
  String host;
  int port;
  String? path;
  String? username;
  String? password;
  int enabled;

  Server({this.id, required this.name, required this.host, this.port = 22, this.path, this.username, this.password, this.enabled = 1});

  Map<String, dynamic> toMap() => {
    'id': id, 'name': name, 'host': host, 'port': port,
    'path': path, 'username': username, 'password': password, 'enabled': enabled,
  };

  factory Server.fromMap(Map<String, dynamic> map) => Server(
    id: map['id'], name: map['name'] ?? '', host: map['host'] ?? '',
    port: map['port'] ?? 22, path: map['path'], username: map['username'],
    password: map['password'], enabled: map['enabled'] ?? 1,
  );
}
