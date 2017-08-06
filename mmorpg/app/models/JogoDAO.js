function JogoDAO(connection){
    
    this._connection = connection();
    console.log("objeto iniciado JogoDAO");

}

JogoDAO.prototype.gerarParametros = function(usuario){

    this._connection.open(function(err,mongoClient){

        mongoClient.collection("jogo",function(err,collection){
            collection.insert({
                usuario : usuario,
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


JogoDAO.prototype.iniciarJogo = function(usuario,callback){
     this._connection.open(function(err,mongoClient){
        mongoClient.collection("jogo",function(err,collection){
            collection.find({usuario:usuario}).toArray(function(err,result){
               
               callback(result[0]);
               
            });
            mongoClient.close();
        });
    });
}




module.exports = function(){

    return JogoDAO;

}