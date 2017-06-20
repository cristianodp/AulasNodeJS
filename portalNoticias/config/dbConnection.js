
const conn = require('mysql');

var instance_db = function(){
  return conn.createConnection({
    host: "52.90.191.182",
    user: "root",
    password: "cdpcdpcdp",
    database: 'dinizDev'
  });

}
module.exports = function(){
  return instance_db;
}
