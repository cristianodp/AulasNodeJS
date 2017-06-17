module.exports = function(){

  this.getNoticias = function(connection, callback){
    connection.query("select * from noticias", callback);
  }

  this.getNoticia = function(byId,connection, callback){
    connection.query("select * from noticias where id_noticia = "+byId, callback);
  }

  this.salvarNoticia = function(noticia, connection, callback){
    connection.query('insert into noticias set ?',noticia, callback);
  }

  return this;
}
