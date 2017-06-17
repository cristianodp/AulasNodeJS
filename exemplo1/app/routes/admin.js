module.exports = function(context){

  context.get('/form_add_noticia',function(req,res){
    res.render("admin/form_add_noticia");
  });
  context.post('/noticias/salvar',function(req,res){
    var noticia = req.body;
    //res.send(noticia);
    const connection = context.config.dbConnection();
    var noticiasModel = context.app.models.noticiasModel;

    noticiasModel.salvarNoticia(noticia, connection, function(error,result){
      if (error == null){
          res.redirect("/noticias");
      }else{
        console.log(error);
      }
    });

  });
}
