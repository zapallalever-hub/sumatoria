from flask import Flask, request

app = Flask(__name__)

@app.route('/')
def suma():
    try:
        n = int(request.args.get('n', '0'))
        if n < 1:
            return 'Por favor ingresa un número entero positivo (n>=1)'
        suma = n * (n + 1) // 2
        return f'La suma de 1 a {n} es: {suma}'
    except ValueError:
        return 'Parámetro inválido'

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
