module.exports.iniciar = function(application,req,res){
    if(req.session.autorizado !== true) {
        res.render('index', { validacao: {} });
    }
    
    var msg = "";
    if(req.query.msg != ''){
        msg = req.query.msg;
    }

    var usuario = req.session.usuario;

    var connection = application.config.dbConnection;
    var JogoDAO = new application.app.models.JogoDAO(connection);
    // res.send

    JogoDAO.iniciarJogo(usuario,function(result){
        
        res.render('jogo', {
              img_casa:req.session.casa
            , jogo: result
            , msg: msg
        });
        
    });
   
   
}

module.exports.sair = function(application,req,res){
    req.session.destroy(function(err){
         res.render('index', { validacao: {} });
    });
}

module.exports.suditos = function(application,req,res){
    if(req.session.autorizado !== true) {
        res.render('index', { validacao: {} });
        return;
    }
    res.render('aldeoes', { validacao: {} });
    
}

module.exports.pergaminhos = function(application,req,res){
    if(req.session.autorizado !== true) {
        res.render('index', { validacao: {} });
        return;
    }

    var connection = application.config.dbConnection;
    var jogoDAO = new application.app.models.JogoDAO(connection);
    var usuario = req.session.usuario;

    jogoDAO.promiseGetAcoes(usuario)
        .then(result=>{
            res.render('pergaminhos', { acoes: result });
        }).catch(reason=>{
            console.warn('Failed: ', reason);
        });

    
    
}


module.exports.ordenar_acao_sudito = function(application,req,res){
   if(req.session.autorizado !== true) {
        res.render('index', { validacao: {} });
        return;
    }
   
    var dadosForm = req.body;

   req.assert('acao','Ação não foi informada').notEmpty();
   req.assert('quantidade','Quantidade não foi informada').notEmpty();
   
   var erros = req.validationErrors();

   if(erros){
       res.redirect('jogo?msg=Erro');
       return;
   }
   
    var connection = application.config.dbConnection;
    var JogoDAO = new application.app.models.JogoDAO(connection);
   
    dadosForm.usuario = req.session.usuario;
    JogoDAO.acao(dadosForm);

    res.redirect('jogo?msg=Sucesso');
}
   

module.exports.revogar_acao = function(application,req,res){
   if(req.session.autorizado !== true) {
        res.render('index', { validacao: {} });
        return;
    }
   
    var url_query = req.query;
   
    var connection = application.config.dbConnection;
    var JogoDAO = new application.app.models.JogoDAO(connection);
   
    var _id = url_query.id_acao;
    JogoDAO.promiseRevogarAcao(_id)
        .then(result=>{
            res.redirect('jogo?msg=Revogada');
        }).catch(reason=>{
            console.warn('Failed: ', reason);
        });

   // res.redirect('jogo?msg=Sucesso');
}
   
