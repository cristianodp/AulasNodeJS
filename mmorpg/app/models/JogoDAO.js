var ObjectID = require('mongodb').ObjectId;

function JogoDAO(connection) {

    this._connection = connection();
    console.log("objeto iniciado JogoDAO");

}

JogoDAO.prototype.gerarParametros = function (usuario) {

    this._connection.open(function (err, mongoClient) {

        mongoClient.collection("jogo", function (err, collection) {
            collection.insert({
                usuario: usuario,
                moeda: 15,
                suditos: 10,
                temor: Math.floor(Math.random() * 1000),
                sabedoria: Math.floor(Math.random() * 1000),
                comercio: Math.floor(Math.random() * 1000),
                magia: Math.floor(Math.random() * 1000)
            });

            mongoClient.close();

        });

    });
    console.log(usuario);

}


JogoDAO.prototype.iniciarJogo = function (usuario, callback) {
    this._connection.open(function (err, mongoClient) {
        mongoClient.collection("jogo", function (err, collection) {
            collection.find({ usuario: usuario }).toArray(function (err, result) {

                callback(result[0]);

            });
            mongoClient.close();
        });
    });
}



JogoDAO.prototype.acao = function (acao) {
    this._connection.open(function (err, mongoClient) {

        mongoClient.collection("acao", function (err, collection) {
            var date = new Date();
            var tempo = null;
            switch(parseInt(acao.acao)){
               case 1 : tempo = 1 * 60 * 60000 ; 
                break;
               case 2 : tempo = 2 * 60 * 60000 ;
                break;
               case 3 : tempo = 3 * 60 * 60000 ;
                break;
               case 4 : tempo = 4 * 60 * 60000 ;
                break;
            }

            acao.acao_termina_em = date.getTime() + tempo;
            collection.insert(acao);

           /* mongoClient.close();*/

        });

        mongoClient.collection("jogo", function (err, collection) {
            var moedas = null;
            switch(parseInt(acao.acao)){
               case 1 : moedas = -2 * acao.quantidade; 
                break;
               case 2 : moedas = -3 * acao.quantidade;
                break;
               case 3 : moedas = -1 * acao.quantidade;
                break;
               case 4 : moedas = -1 * acao.quantidade;
                break;
            }
            collection.update(
                { usuario : acao.usuario },
                { $inc: {moeda : moedas} }
            );
            mongoClient.close();

        });

    });

}


JogoDAO.prototype.promiseGetAcoes = function (usuario) {

  return new Promise(resolve => {

    this._connection.open(function (err, mongoClient) {
        if (err != null){
            resolve(err);
            return;
        }
        mongoClient.collection("acao", function (err, collection) {
            var data =  new Date();
            var current_time = data.getTime();
            collection.find({ usuario: usuario, acao_termina_em : {$gt:current_time}}).toArray(function (err, result) {
                if (err != null){
                    resolve(err);
                    return;
                }
                
                resolve(result);

            });
            mongoClient.close();
        });
    });

  });

    
   
}


JogoDAO.prototype.promiseRevogarAcao = function (_id) {
    return new Promise(resolve => {

    this._connection.open(function (err, mongoClient) {
        if (err != null){
            resolve(err);
            return;
        }
        mongoClient.collection("acao", function (err, collection) {
        
            collection.remove(
                {_id: ObjectID(_id)},
                function(err,result){
                    if (err != null){
                        resolve(err);
                        return;
                    }
                    resolve(result);
                }
            );
            
            mongoClient.close();
        });
    });

  });

}


module.exports = function () {

    return JogoDAO;

}