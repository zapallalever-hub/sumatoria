import 'dart:io';

void main() async {
  final port = int.parse(Platform.environment['PORT'] ?? '8080');

  final server = await HttpServer.bind(InternetAddress.anyIPv4, port);

  print('Servidor corriendo en puerto $port');

  await for (HttpRequest request in server) {
    final query = request.uri.queryParameters;
    final n = int.tryParse(query['n'] ?? '');

    if (n == null || n < 1) {
      request.response
        ..statusCode = 400
        ..write('Parámetro "n" inválido');
    } else {
      final suma = n * (n + 1) ~/ 2;
      request.response.write('La suma de 1 a $n es: $suma');
    }

    await request.response.close();
  }
}
