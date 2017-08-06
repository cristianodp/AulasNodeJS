module.exports.iniciar = function(application,req,res){
    if(req.session.autorizado !== true) {
        res.render('index', { validacao: {} });
    }
    
    var usuario = req.session.usuario;

    var connection = application.config.dbConnection;
    var JogoDAO = new application.app.models.JogoDAO(connection);
    // res.send

    JogoDAO.iniciarJogo(usuario,function(result){
        
        res.render('jogo', {
              img_casa:req.session.casa
            , jogo: result
        });
        
    });
   
   
}

module.exports.sair = function(application,req,res){
    req.session.destroy(function(err){
         res.render('index', { validacao: {} });
    });
}

module.exports.suditos = function(application,req,res){
    res.render('aldeoes', { validacao: {} });
    
}

module.exports.pergaminhos = function(application,req,res){
    res.render('pergaminhos', { validacao: {} });
    
}
