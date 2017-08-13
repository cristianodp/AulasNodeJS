var crypto = require("crypto");

function UsuariosDAO(connection){
    
    this._connection = connection();
    console.log("objsto iniciado");

}

UsuariosDAO.prototype.inserirUsuario = function(usuario){

    this._connection.open(function(err,mongoClient){

        mongoClient.collection("usuarios",function(err,collection){
            
            var senha = crypto.createHash("md5").update(usuario.senha).digest("hex");
            usuario.senha = senha;

            collection.insert(usuario);
            
            mongoClient.close();

        });

    });
    console.log(usuario);


}

UsuariosDAO.prototype.autenticar = function(usuario,req,callback){

     this._connection.open(function(err,mongoClient){

        mongoClient.collection("usuarios",function(err,collection){
            /*collection.find({
                    usuario:{$eq: usuario.usuario}, 
                    senha:{$eq:usuario.senha}
                });*/

            var senha = crypto.createHash("md5").update(usuario.senha).digest("hex");
            usuario.senha = senha;

            collection.find(usuario).toArray(function(err,result){
               
               if (result[0] != undefined){
                   req.session.autorizado = true;
                   req.session.usuario = result[0].usuario;
                   req.session.casa = result[0].casa;

                   callback(true);
               }else{
                   callback(false);
               }

            });

            mongoClient.close();

        });

    });

}

module.exports = function(){

    return UsuariosDAO;

}