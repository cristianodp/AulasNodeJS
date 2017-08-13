var http = require("http");
var opcoes = {
    hostname : 'localhost',
    method:'get',
    port:80,
    path: "/teste",
    headers:{
        'Accept' :'application/json',
        'Content-type':'application/json'
    }

}
/*
//Content-type
var html = 'nome=José';
var json= {nome:'José'};
var string_json = JSON.stringify(json);

var buffer_corpo_response = [];
var req = http.request(opcoes,function(res){

    res.on('data', function(pedaco){
        //console.log(' ' + pedaco);
        buffer_corpo_response.push(pedaco);
    });

    res.on('end', function(){
        var corpo_reponse = Buffer.concat(buffer_corpo_response).toString();
        console.log(corpo_reponse);
    });

    res.on('error',function(err){

    });
});

req.write(string_json);
req.end();
*/

var buffer_corpo_response = [];
http.get(opcoes,function(res){

    res.on('data', function(pedaco){
        //console.log(' ' + pedaco);
        buffer_corpo_response.push(pedaco);
    });

    res.on('end', function(){
        var corpo_reponse = Buffer.concat(buffer_corpo_response).toString();
        console.log(corpo_reponse);
        console.log(res.statusCode);
    });

    res.on('error',function(err){

    });
});