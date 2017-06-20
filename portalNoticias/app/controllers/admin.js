module.exports.form_add_noticia = function(context,req,res){
  res.render("admin/form_add_noticia",{validacao:{},noticia:{}});
}

module.exports.noticias_salvar = function(context,req,res){

  var noticia = req.body;

  req.assert('titulo','Título é obrigatório').notEmpty();
  req.assert('resumo','Resumo é obrigatório').notEmpty();
  req.assert('resumo','Resumo deve ter ente 10 e 100 caracteres').len(10,100);
  req.assert('autor','Autor é obrigatório').notEmpty();
  req.assert('data_noticia','Data é obrigatória').notEmpty().isDate({format:'YYYY-MM-DD'});
  req.assert('noticia','Noticia é obrigatória').notEmpty();

  var erros = req.validationErrors();
  console.log(erros);
  if (erros){
    res.render("admin/form_add_noticia",{validacao : erros, noticia : noticia });
    return ;
  }

  const connection = context.config.dbConnection();
  var noticiasModel = new context.app.models.NoticiasDAO(connection);
  console.log('Antes chamar salvarNoticia');
  noticiasModel.salvarNoticia(noticia,function(error,result){
      console.log('errp ='+error);
    //if (error == false){
        res.redirect("/noticias");
  //  }else{
  //    console.log(error);
  //  }
  });
}
