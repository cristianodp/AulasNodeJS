
const conn = require('mysql');

var instance_db = function(){
  console.log("Conexao aberta ");
  return conn.createConnection({
    host: "52.90.191.182",
    user: "root",
    password: "cdpcdpcdp",
    database: 'dinizDev'
  });

}

module.exports = function(){
  console.log("Instancia variavem de conexao");
  return instance_db;
}
