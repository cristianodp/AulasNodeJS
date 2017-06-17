//var dbConnection = require("../../config/dbConnection");
module.exports = function(app){
  app.get('/noticias',function(req,res){


    const connection = app.config.dbConnection();

    connection.query("select * from noticias", function(error,result){

      var json = JSON.stringify(result.rows, null, "    ");
      console.log(json);
      res.render("noticias/noticias", { noticias : result.rows });

    });

    //res.render("noticias/noticias");
  });
}
