/*importar o mongodb*/

var mongo = require("mongodb");


var connMongoDB = function () {

    var db = new mongo.Db(
        'got',
        new mongo.Server(
            'localhost', //string coneção do endereçõ do servidor
            27017, //porta 
            {}
        ),
        {}
    );

    return db;
}

module.exports = function () {

    return connMongoDB;

}

