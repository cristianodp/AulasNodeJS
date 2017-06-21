/*Importar as configuracoes do servidor*/
var app = require('./config/server');

/*parametrizar a porta de escuta*/
var server = app.listen(80, function(){
  console.log('Servidor online na porta 80');
});

var io = require('socket.io').listen(server);
app.set('io',io);

/*Criar coneção para websocket*/
io.on('connection',function(socket){
  console.log('Usuário conectou');
  
    socket.on('disconnect', function(){
    console.log('Usuário desconectouuu');
  });

  socket.on('msgParaServidor',function(data){
    /*dialogo*/
    socket.emit('msgParaCliente',{apelido:data.apelido
                                ,mensagem:data.mensagem});

    socket.broadcast.emit('msgParaCliente',{apelido:data.apelido
                                ,mensagem:data.mensagem});

    /*participantes*/
    socket.emit('participantesParaCliente',{apelido:data.apelido});

    socket.broadcast.emit('participantesParaCliente',{apelido:data.apelido});

  });

});
