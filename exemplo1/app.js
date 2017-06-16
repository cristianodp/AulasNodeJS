var app = require("./config/server");




app.get('/tecnologia',function(req,res){
  res.render("sessao/tecnologia");
});


app.listen(80, function(){

  console.log("Servidor rodando na porta 3000");

})
