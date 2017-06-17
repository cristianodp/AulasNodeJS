var app = require("./config/server");

//var rotasNoticias = require('./app/routes/noticias')(app);

//var rotasHome = require('./app/routes/home')(app);

//var rotasFormAddNoticias = require('./app/routes/form_add_noticia')(app);

app.listen(3000, function(){

  console.log("Servidor rodando na porta 3000");

})
