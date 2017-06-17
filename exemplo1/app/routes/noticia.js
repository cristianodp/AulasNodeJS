module.exports = function(context){
  context.get('/noticia',function(req,res){
    const connection = context.config.dbConnection();

    var models = context.app.models;
    var noticiasModel = models.noticiasModel;

    noticiasModel.getNoticia(2,connection, function(error,result){
      res.render("noticias/noticia", { noticias : result });
    });

  });

}
