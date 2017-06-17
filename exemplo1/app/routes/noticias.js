module.exports = function(context){

  context.get('/noticias',function(req,res){

    const connection = context.config.dbConnection();
    var models = context.app.models;

    var noticiasModel = models.noticiasModel;

    noticiasModel.getNoticias(connection, function(error,result){
      res.render("noticias/noticias", { noticias : result });
    });

  });
}
