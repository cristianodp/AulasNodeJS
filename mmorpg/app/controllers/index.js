module.exports.iniciar = function (application, req, res) {
    res.render('index', { validacao: {} });
}

module.exports.autenticar = function (application, req, res) {
    var dadosForm = req.body;

    req.assert('usuario', 'Usuário não deve ser vazio').notEmpty();
    req.assert('senha', 'Senha não deve ser vazia').notEmpty();

    var erros = req.validationErrors();

    if (erros) {
        res.render('index', { validacao: erros });
        return;
    }

    var connection = application.config.dbConnection;
    var UsuariosDAO = new application.app.models.UsuariosDAO(connection);
    // res.send

    UsuariosDAO.autenticar(dadosForm,req,function(sucess){
        if (sucess){
            res.redirect("jogo");
        }else{
            res.render("index",{validacao:[{msg:"Usuário ou senha inválidos!"}]})
            //res.send("Não Autenticou");
        }
    });



}

