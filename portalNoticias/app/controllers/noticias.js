module.exports.noticias = function(context,req,res){
  const connection = context.config.dbConnection();

  var noticiasModel = new context.app.models.NoticiasDAO(connection);
  noticiasModel.getNoticias(function(error,result){
    res.render("noticias/noticias", { noticias : result });
  });
}

module.exports.noticia = function(context,req,res){
  const connection = context.config.dbConnection();
  
  var id_noticia = req.query;
  var noticiasModel = new context.app.models.NoticiasDAO(connection);
  noticiasModel.getNoticia(id_noticia,function(error,result){
    res.render("noticias/noticia", { noticia : result[0] });
  });
}
