var dbConnection = require("../../config/dbConnection");
module.exports =function(app){
  app.get('/noticias',function(req,res){

    const connection = dbConnection();

    connection.query("select * from noticias", function(error,result){
        console.log(result.rowCount + ' rows were received');
        var json = JSON.stringify(result.rows, null, "    ");
        console.log(json);
        res.render(json);
    });

    //res.render("noticias/noticias");
  });
}
