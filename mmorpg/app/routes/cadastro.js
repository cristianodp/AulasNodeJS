module.exports = function(application){
	application.get('/cadastro', function(req, res){
		application.app.controllers.cadastro.iniciar(application,req,res);
	});

	application.post('/cadastrar', function(req, res){
		application.app.controllers.cadastro.incluir(application,req,res);
	});
}