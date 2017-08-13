var express = require('express'),
    bodyParser = require('body-parser'),
    mongodb = require('mongodb');


var app = express();

app.use(bodyParser.urlencoded({extended:true}));
app.use(bodyParser.json());

var port = 8080;
var db = new mongodb.Db(
    'instagram',
    new mongodb.Server('localhost',27017,{}),
    {}
);


app.listen(port);

console.log('Servidor HTTP esta escutando na porta '+port);


app.get("/",function(req, res){
    res.send({msg:'olá'});
});

app.post('/api',function(req,res){
    var dados = req.body;

    db.open(function(err, mongoclient){
        mongoclient.collection('postagens', function(err, collection){
            collection.insert(dados, function(err, records){
                if (err){
                    res.json(err);
                }else{
                    res.json(records);
                }
                mongoclient.close();
            });
        });
    });

    res.send(dados);
});
