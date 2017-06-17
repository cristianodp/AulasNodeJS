
const pg = require('pg');

var instance_db = function(){
  console.log("Conexao aberta ");
  return new pg.Pool({
      user: 'postgres', //env var: PGUSER
      database: 'dinizDev', //env var: PGDATABASE
      password: 'cdpcdpcdp', //env var: PGPASSWORD
      host: '52.90.191.182', // Server hosting the postgres database
      port: 5432, //env var: PGPORT
      max: 10, // max number of clients in the pool
      idleTimeoutMillis: 30000 // how long a client is allowed to remain idle before being closed
    });

}

module.exports = function(){
  console.log("Instancia variavem de conexao");
  return instance_db;
}
