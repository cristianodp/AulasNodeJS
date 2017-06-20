module.exports = function(context){

  context.get('/form_add_noticia',function(req,res){
      context.app.controllers.admin.form_add_noticia(context,req,res);
  });
  context.post('/noticias/salvar',function(req,res){
      context.app.controllers.admin.noticias_salvar(context,req,res);
  });
}
