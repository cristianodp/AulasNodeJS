module.exports = function(context){

  context.get('/noticias',function(req,res){

    context.app.controllers.noticias.noticias(context,req,res);
  });

  context.get('/noticia',function(req,res){
    context.app.controllers.noticias.noticia(context,req,res);

  });
}
