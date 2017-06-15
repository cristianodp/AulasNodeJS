CREATE OR REPLACE PACKAGE BODY SULMAQ_AGRUPA_ITENS IS

   /*****************************************************************************************/
   /************************* PROJETO 157387 - Agrupamento de Itens *************************/
   /*****************************************************************************************/
   FUNCTION RETORNA_MNEMONICO ( pi_itempr_id     IN titens_empr.id%TYPE
                              , pi_tmasc_item_id IN tmasc_item.id%TYPE
                              , pi_tipo          IN VARCHAR2 ) RETURN VARCHAR2 IS
   
   v_oportunidade VARCHAR2(30);
   v_setor        VARCHAR2(30);
   v_seq          VARCHAR2(30);
   v_count        NUMBER(1);

   BEGIN
      v_count := 1;

      FOR i IN ( SELECT tvar.mnemonico
                   FROM tconfig_itens config
                      , tvariaveis    tvar
                  WHERE config.tvar_id       = tvar.id
                    AND config.itempr_id     = pi_itempr_id
                    AND config.tmasc_item_id = pi_tmasc_item_id
                  ORDER BY config.seq )
      LOOP
         IF v_count = 1 THEN
            v_oportunidade := i.mnemonico;
         ELSIF v_count = 2 THEN
            v_setor := i.mnemonico;
         ELSIF v_count = 3 THEN
            v_seq := i.mnemonico;
         ELSE
            EXIT;
         END IF;

         INC(v_count);
      END LOOP;
   
      IF pi_tipo = 'OPORTUNIDADE' THEN
         RETURN v_oportunidade;
      ELSIF pi_tipo = 'SETOR' THEN
         RETURN v_setor;
      ELSIF pi_tipo = 'SEQ' THEN
         RETURN v_seq;
      ELSIF pi_tipo = 'SETOR_SEQ' THEN
         RETURN v_setor||' '||v_seq;
      ELSE
         RETURN NULL;
      END IF;
   END RETORNA_MNEMONICO;
   
   FUNCTION RETORNA_DESCRICAO_SULMAQ ( pi_itpdv_id      IN titens_pdv.id%TYPE
                                     , pi_tmasc_item_id IN tmasc_item.id%TYPE ) RETURN VARCHAR2 IS
      v_descricao VARCHAR2(200);
      v_idioma_id tidiomas.id%TYPE;
   BEGIN
      BEGIN
         SELECT pdv.idiomas_id
           INTO v_idioma_id
           FROM tpedidos_venda pdv
              , titens_pdv     itpdv
          WHERE pdv.id   = itpdv.pdv_id
            AND itpdv.id = pi_itpdv_id;
      EXCEPTION
         WHEN NO_DATA_FOUND THEN
            v_idioma_id := NULL;
      END;
      
      BEGIN
         SELECT SUBSTR(nome,1,200)
           INTO v_descricao
           FROM sdi_itempdv_descritivos
          WHERE itpdv_id              = pi_itpdv_id
            AND NVL(tmasc_item_id, 0) = NVL(pi_tmasc_item_id, 0)
            AND tidiomas_id           = NVL(v_idioma_id, 1)
            AND nome                  IS NOT NULL;
      EXCEPTION
         WHEN NO_DATA_FOUND OR TOO_MANY_ROWS THEN
            BEGIN
               SELECT NVL(itpdv.descricao, itcm.descricao)
                 INTO v_descricao
                 FROM titens_pdv       itpdv
                    , titens_comercial itcm
                WHERE itpdv.itcm_id               = itcm.id
                  AND itpdv.id                    = pi_itpdv_id
                  AND NVL(itpdv.tmasc_item_id, 0) = NVL(pi_tmasc_item_id, 0);
            EXCEPTION
               WHEN NO_DATA_FOUND THEN
                  v_descricao := NULL;
            END;
      END;
      
      RETURN v_descricao;
   END RETORNA_DESCRICAO_SULMAQ;

   PROCEDURE INSERE_WG_FSULMAQ_COM008 ( pi_empr_id   IN tempresas.id%TYPE
                                      , pi_num_opp   IN VARCHAR2
                                      , pi_setor_seq IN VARCHAR2
                                      , pi_tipo      IN VARCHAR2 --Parametro de controle (e chamada em varios lugares)
                                      , pi_identa    IN NUMBER DEFAULT 1 )
                                      IS

   --Type -> Oportunidade
   v_idx_opp NUMBER;      
   TYPE t_opp IS RECORD ( num_opp       sdi_orcfocco_oportcrm.num_opp%TYPE
                        , pdv_id        tpedidos_venda.id%TYPE
                        , num_pedido    tpedidos_venda.num_pedido%TYPE );
   TYPE t_tipo_opp IS TABLE OF t_opp INDEX BY PLS_INTEGER;
   v_opp t_tipo_opp;

   --Type -> Setor/Sequencia
   v_idx_set NUMBER;      
   TYPE t_set IS RECORD ( cod_item      titens_comercial.cod_item%TYPE
                        , descricao     titens_comercial.descricao%TYPE
                        , itempr_id     titens_empr.id%TYPE
                        , tmasc_item_id tmasc_item.id%TYPE
                        , setor_seq     sdi_itpdv_indice.setor_seq%TYPE
                        , qtde          titens_pdv.qtde%TYPE
                        , qtde_pend     titens_pdv.qtde_sldo%TYPE
                        , vlr_total     NUMBER
                        , vlr_pend      NUMBER
                        , itpdv_id      titens_pdv.id%TYPE );
   TYPE t_tipo_set IS TABLE OF t_set INDEX BY PLS_INTEGER;
   v_set t_tipo_set;
   
   v_idx2 NUMBER;      
   TYPE t_reg2 IS RECORD ( cod_item      titens_comercial.cod_item%TYPE
                         , descricao     titens_comercial.descricao%TYPE
                         , itempr_id     titens_empr.id%TYPE
                         , tmasc_item_id tmasc_item.id%TYPE
                         , num_opp       sdi_orcfocco_oportcrm.num_opp%TYPE
                         , setor_seq     sdi_itpdv_indice.setor_seq%TYPE
                         , qtde          titens_pdv.qtde%TYPE
                         , vlr_total     NUMBER
                         , vlr_pend      NUMBER
                         , itpdv_id      titens_pdv.id%TYPE
                         , pdv_id        tpedidos_venda.id%TYPE
                         , num_pedido    tpedidos_venda.num_pedido%TYPE
                         );
   TYPE t_tipo2 IS TABLE OF t_reg2 INDEX BY PLS_INTEGER;
   v_reg2 t_tipo2;

   c_cursor_opp    FOCCO3I_UTIL.REFCUR;
   c_cursor_set    FOCCO3I_UTIL.REFCUR;
   c_cursor        FOCCO3I_UTIL.REFCUR;
   v_query_opp     VARCHAR2(4000);
   v_query_set     VARCHAR2(4000);
   v_query         VARCHAR2(4000);
   v_ordenacao     NUMBER := 0;
   v_cod_item      VARCHAR2(50);
   v_qtde_agrupada NUMBER;
   v_descon_itens  VARCHAR2(4000);
   v_vlr_custo     NUMBER(17,8);

      PROCEDURE INSERE_WG ( pi_ordenacao           IN NUMBER
                          , pi_nivel               IN NUMBER
                          , pi_cod_item            IN VARCHAR2
                          , pi_descricao           IN VARCHAR2
                          , pi_itempr_id           IN titens_empr.id%TYPE
                          , pi_tmasc_item_id       IN tmasc_item.id%TYPE
                          , pi_num_opp             IN sdi_orcfocco_oportcrm.num_opp%TYPE
                          , pi_setor_seq           IN sdi_itpdv_indice.setor_seq%TYPE
                          , pi_qtde                IN NUMBER --Quantidade do item no pedido
                          , pi_qtde_sldo           IN NUMBER --Quantidade pendente do item no pedido
                          , pi_qtde_a_agrupar      IN NUMBER --Quantidade Disponivel para Agrupamento
                          , pi_qtde_agrupada       IN NUMBER --Quantidade Ja Agrupada
                          , pi_vlr_total_ori       IN NUMBER
                          , pi_vlr_total           IN NUMBER
                          , pi_vlr_pend            IN NUMBER
                          , pi_itpdv_id_nvl_1      IN titens_pdv.id%TYPE
                          , pi_itpdv_id_nvl_2      IN titens_pdv.id%TYPE
                          , pi_itpdv_id_nvl_3      IN titens_pdv.id%TYPE
                          , pi_tipo                IN VARCHAR2
                          , pi_pdv_id              IN tpedidos_venda.id%TYPE
                          , pi_num_pedido          IN tpedidos_venda.num_pedido%TYPE
                          , pi_custo_medio         IN NUMBER
                          , pi_alterado            IN NUMBER
--                          , pi_onde                IN VARCHAR2 DEFAULT DBMS_UTILITY.format_call_stack
                          ) IS
      BEGIN
         INSERT INTO wg_fsulmaq_com008
                   ( ordenacao
                   , selecionado
                   , nivel
                   , cod_item
                   , descricao
                   , itempr_id
                   , tmasc_item_id
                   , num_opp
                   , setor_seq
                   , qtde
                   , qtde_sldo
                   , qtde_a_agrupar
                   , qtde_agrupada
                   , vlr_total_ori
                   , vlr_total
                   , vlr_pend
                   , itpdv_id_nvl_1
                   , itpdv_id_nvl_2
                   , itpdv_id_nvl_3
                   , tipo
                   , pdv_id
                   , num_pedido
                   , custo_medio
                   , alterado
--                   , ONDE
                   )
            VALUES ( pi_ordenacao
                   , 0
                   , pi_nivel
                   , pi_cod_item
                   , pi_descricao
                   , pi_itempr_id
                   , pi_tmasc_item_id
                   , pi_num_opp
                   , pi_setor_seq
                   , pi_qtde
                   , pi_qtde_sldo
                   , pi_qtde_a_agrupar
                   , pi_qtde_agrupada
                   , pi_vlr_total_ori
                   , pi_vlr_total
                   , pi_vlr_pend
                   , pi_itpdv_id_nvl_1
                   , pi_itpdv_id_nvl_2
                   , pi_itpdv_id_nvl_3
                   , pi_tipo
                   , pi_pdv_id
                   , pi_num_pedido
                   , pi_custo_medio
                   , pi_alterado
--                   , pi_onde 
                   );
      END INSERE_WG;

   BEGIN
      DELETE wg_fsulmaq_com008
       WHERE tipo = pi_tipo;

      v_descon_itens := FOCCO3I_UTIL.RETORNA_PARAMETRO('IDE157387_1_SULMAQ','DESCON_ITENS',pi_empr_id,NULL);

      -------------------------------------------------------------------
      ------------------------| PEDIDO FATURADO |------------------------
      ------------------------|     1? NIVEL    |------------------------
      -------------------------------------------------------------------
      
      v_query_opp := ' SELECT opp.num_opp    num_opp
                            , pdv.id         pdv_id
                            , pdv.num_pedido num_pedido
                         FROM sdi_pdv_fut opp  
                            , tpedidos_venda        pdv
                        WHERE opp.pdv_id            = pdv.id
                          AND pdv.tipo              = ''PDV''
                          AND '||FOCCO3I_UTIL.INTERVALO('opp.num_opp', pi_num_opp, 'N');

      --Dados utilizados na tela FSULMAQ_COM008
      IF pi_tipo = 'CONSULTA' THEN
         OPEN c_cursor_opp FOR v_query_opp;
         LOOP
            FETCH c_cursor_opp BULK COLLECT INTO v_opp;
            IF v_opp.COUNT = 0 THEN
               EXIT;
            END IF;

            IF v_opp.COUNT > 0 THEN
               FOR v_idx_opp IN v_opp.FIRST..v_opp.LAST
               LOOP
                  v_query_set := ' SELECT itcm.cod_item                        cod_item
                                        /*, NVL(itpdv.descricao, itcm.descricao) descricao*/
                                        , SULMAQ_AGRUPA_ITENS.RETORNA_DESCRICAO_SULMAQ(itpdv.id, itpdv.tmasc_item_id) descricao
                                        , itempr.id                            itempr_id
                                        , itpdv.tmasc_item_id                  tmasc_item_id
                                        , sulmaq_agrupa_itens.retorna_mnemonico( itempr.id, itpdv.tmasc_item_id, ''SETOR_SEQ'' ) setor_seq
                                        , itpdv.qtde                           qtde
                                        , itpdv.qtde_sldo                      qtde_pend
                                        , itpdv.vlr_liq_ipi*itpdv.qtde         vlr_total
                                        , NULL                                 vlr_pend
                                        , itpdv.id                             itpdv_id
                                     FROM titens_pdv       itpdv
                                        , titens_comercial itcm
                                        , titens_empr      itempr
                                    WHERE itpdv.itcm_id   = itcm.id
                                      AND itcm.itempr_id  = itempr.id
                                      AND itpdv.qtde_canc < itpdv.qtde
                                      AND itpdv.pdv_id    = '||v_opp(v_idx_opp).pdv_id||' ';
         
                  IF pi_setor_seq IS NOT NULL THEN
                     v_query_set := v_query_set||' AND '||
                                 FOCCO3I_UTIL.INTERVALO( 'SULMAQ_AGRUPA_ITENS.RETORNA_MNEMONICO(itempr.id, itpdv.tmasc_item_id, ''SETOR_SEQ'') '
                                                       , pi_setor_seq
                                                       , 'A' );
                  END IF;

                  IF v_descon_itens IS NOT NULL THEN
                     v_query_set := v_query_set||' AND INSTR( '',''||'''||v_descon_itens||'''||'','', '',''||itcm.cod_item||'','', 1 ) = 0 ';
                  END IF;

                  v_query_set := v_query_set||' ORDER BY setor_seq     ASC
                                                       , itcm.cod_item ASC ';

                  OPEN c_cursor_set FOR v_query_set;
                  LOOP
                     FETCH c_cursor_set BULK COLLECT INTO v_set;
                     IF v_set.COUNT = 0 THEN
                        EXIT;
                     END IF;

                     IF v_set.COUNT > 0 THEN
                        FOR v_idx_set IN v_set.FIRST..v_set.LAST
                        LOOP
                           INC(v_ordenacao);
                           INSERE_WG ( PI_ORDENACAO      => v_ordenacao
                                     , PI_NIVEL          => 1
                                     , PI_COD_ITEM       => v_set(v_idx_set).cod_item
                                     , PI_DESCRICAO      => v_set(v_idx_set).descricao
                                     , PI_ITEMPR_ID      => v_set(v_idx_set).itempr_id
                                     , PI_TMASC_ITEM_ID  => v_set(v_idx_set).tmasc_item_id
                                     , PI_NUM_OPP        => v_opp(v_idx_opp).num_opp
                                     , PI_SETOR_SEQ      => v_set(v_idx_set).setor_seq
                                     , PI_QTDE           => v_set(v_idx_set).qtde --Quantidade do Item no Pedido
                                     , PI_QTDE_SLDO      => NULL                  --Quantidade Pendente
                                     , PI_QTDE_A_AGRUPAR => NULL
                                     , PI_QTDE_AGRUPADA  => NULL
                                     , PI_VLR_TOTAL_ORI  => ROUND(v_set(v_idx_set).vlr_total,2)
                                     , PI_VLR_TOTAL      => ROUND(v_set(v_idx_set).vlr_total,2)
                                     , PI_VLR_PEND       => ROUND(v_set(v_idx_set).vlr_pend,2)
                                     , PI_ITPDV_ID_NVL_1 => v_set(v_idx_set).itpdv_id
                                     , PI_ITPDV_ID_NVL_2 => NULL
                                     , PI_ITPDV_ID_NVL_3 => NULL
                                     , PI_TIPO           => pi_tipo
                                     , PI_PDV_ID         => v_opp(v_idx_opp).pdv_id
                                     , PI_NUM_PEDIDO     => v_opp(v_idx_opp).num_pedido
                                     , PI_CUSTO_MEDIO    => NULL
                                     , PI_ALTERADO       => NULL
                                     );

                           ---------------------------------------------------------------------
                           ------------------------| PEDIDO NECESSARIO |------------------------
                           ------------------------|      2? NIVEL     |------------------------
                           ---------------------------------------------------------------------
                           FOR c_sul IN (SELECT sul.num_opp
                                              , sul.setor_seq
                                           FROM tsulmaq_vinc_pdv sul
                                              , titens_pdv       itpdv
                                          WHERE sul.itpdv_id = itpdv.id
                                            AND itpdv.id     = v_set(v_idx_set).itpdv_id)
                           LOOP
                              FOR c_vinc IN (SELECT itcm.cod_item                         cod_item
                                                  /*, NVL (itpdv.descricao, itcm.descricao) descricao*/
                                                  , SULMAQ_AGRUPA_ITENS.RETORNA_DESCRICAO_SULMAQ(itpdv.id, itpdv.tmasc_item_id) descricao
                                                  , itempr.ID                             itempr_id
                                                  , itpdv.tmasc_item_id                   tmasc_item_id
                                                  , itpdv.qtde                            qtde
                                                  , sul.qtde                              qtde_agrupada
                                                  , sul.num_opp                           num_opp
                                                  , sul.setor_seq                         setor_seq
                                                  , itpdv.ID                              itpdv_id
                                                  , pdv.ID                                pdv_id
                                                  , pdv.num_pedido                        num_pedido
                                                  , itpdv.qtde - sul.qtde                 qtde_sldo
                                                  , itpdv.vlr_liq_ipi                     vlr_total
                                                  , sul.valor                             valor
                                               FROM tsulmaq_vinc_pdv      sul
                                                  , sdi_orcfocco_oportcrm opp
                                                  , tpedidos_venda        pdv
                                                  , titens_pdv            itpdv
                                                  , titens_comercial      itcm
                                                  , titens_empr           itempr
                                              WHERE sul.num_opp           = opp.num_opp
                                                AND sul.setor_seq         = sulmaq_agrupa_itens.retorna_mnemonico(itempr.ID, itpdv.tmasc_item_id, 'SETOR_SEQ')
                                                AND opp.id_tpedidos_venda = pdv.ID
                                                AND pdv.ID                = itpdv.pdv_id
                                                AND itpdv.itcm_id         = itcm.ID
                                                AND itcm.itempr_id        = itempr.ID
                                                AND pdv.tipo              = 'PDV'
                                                AND opp.revisao           = (SELECT MAX(opp2.revisao)
                                                                               FROM sdi_orcfocco_oportcrm opp2
                                                                                  , tpedidos_venda pdv2
                                                                              WHERE pdv2.ID      = opp2.id_tpedidos_venda
                                                                                AND opp2.num_opp = opp.num_opp
                                                                                AND pdv2.tipo    = pdv.tipo)
                                                AND sul.num_opp           = c_sul.num_opp
                                                AND sul.setor_seq         = c_sul.setor_seq
                                                --AND SDI_PERC_LIB_ITPDV(itpdv.id, 'PPCPM') = 100 ---Impedir que seja calculado o valor dos agrupamentos se n?o estiver 100% na Engenharia de produtos,
                                                AND sul.itpdv_id          = v_set(v_idx_set).itpdv_id)
                              LOOP
                                 INC(v_ordenacao);

                                 IF pi_identa = 1 THEN
                                    v_cod_item := LPAD(' ',10,' ')||c_vinc.cod_item;
                                 ELSE
                                    v_cod_item := c_vinc.cod_item;
                                 END IF;

                                 INSERE_WG ( PI_ORDENACAO      => v_ordenacao
                                           , PI_NIVEL          => 2
                                           , PI_COD_ITEM       => v_cod_item
                                           , PI_DESCRICAO      => c_vinc.descricao
                                           , PI_ITEMPR_ID      => c_vinc.itempr_id
                                           , PI_TMASC_ITEM_ID  => c_vinc.tmasc_item_id
                                           , PI_NUM_OPP        => c_vinc.num_opp
                                           , PI_SETOR_SEQ      => c_vinc.setor_seq
                                           , PI_QTDE           => c_vinc.qtde_agrupada --Quantidade Agrupada do Item
                                           , PI_QTDE_SLDO      => NULL                 --Quantidade Pendente
                                           , PI_QTDE_A_AGRUPAR => NULL
                                           , PI_QTDE_AGRUPADA  => NULL
                                           , PI_VLR_TOTAL_ORI  => NULL--c_vinc.vlr_total
                                           , PI_VLR_TOTAL      => ROUND(c_vinc.valor,2)
                                           , PI_VLR_PEND       => NULL
                                           , PI_ITPDV_ID_NVL_1 => v_set(v_idx_set).itpdv_id
                                           , PI_ITPDV_ID_NVL_2 => c_vinc.itpdv_id
                                           , PI_ITPDV_ID_NVL_3 => NULL
                                           , PI_TIPO           => pi_tipo
                                           , PI_PDV_ID         => c_vinc.pdv_id
                                           , PI_NUM_PEDIDO     => c_vinc.num_pedido
                                           , PI_CUSTO_MEDIO    => NULL
                                           , PI_ALTERADO       => NULL
                                           );

                                 -------------------------------------------------------------------
                                 -----------------------| PEDIDO EXPEDIC?O  |-----------------------
                                 -----------------------|     3? NIVEL      |-----------------------
                                 -------------------------------------------------------------------
                                 FOR c_exp IN ( SELECT itcm.cod_item                        cod_item
                                                     , NVL(itpdv.descricao, itcm.descricao) descricao
                                                     , itempr.id                            itempr_id
                                                     , itpdv.tmasc_item_id                  tmasc_item_id
                                                     --, ((itpdv.qtde/c_vinc.qtde)*NVL(c_vinc.qtde_agrupada,1)) qtde                 -- Comentado  Sol. 295114
                                                     , (((itpdv.qtde-itpdv.qtde_canc)/greatest(nvl(c_vinc.qtde,1),1) )*NVL(c_vinc.qtde_agrupada,1)) qtde -- Adicionado Sol. 295114
                                                     , itpdv.qtde_sldo                      qtde_sldo
                                                     , fab.oportunidade                     num_opp
                                                     , fab.setor_seq                        setor_seq
                                                     , itpdv.id                             itpdv_id
                                                     , pdv.id                               pdv_id
                                                     , pdv.num_pedido                       num_pedido
                                                     , itpdv.qtde_atend                     qtde_faturada
                                                     , fab.alterado                         alterado
                                                     , fab.vlr_total                        vlr_total_alterado
                                                  FROM sdi_pdv_expedicao     exp
                                                     , tpedidos_venda        pdv
                                                     , titens_pdv            itpdv
                                                     , sdi_listas_fabricacao fab
                                                     , titens_comercial      itcm
                                                     , titens_empr           itempr
                                                 WHERE exp.pdv_id     = pdv.id
                                                   AND pdv.id         = itpdv.pdv_id
                                                   AND itpdv.id       = fab.itpdv_id
                                                   AND itpdv.itcm_id  = itcm.id
                                                   AND itcm.itempr_id = itempr.id
                                                   AND itpdv.qtde_canc < itpdv.qtde
                                                   AND pdv.tipo       = 'PDV'
                                                   AND exp.num_opp    = c_vinc.num_opp
                                                   AND fab.setor_seq  = c_vinc.setor_seq )
                                 LOOP
                                    INC(v_ordenacao);

                                    IF pi_identa = 1 THEN
                                       v_cod_item := LPAD(' ',20,' ')||c_exp.cod_item;
                                    ELSE
                                       v_cod_item := LPAD(' ',10,' ')||c_exp.cod_item;
                                    END IF;

                                    IF c_exp.tmasc_item_id IS NULL THEN
                                       BEGIN
                                          SELECT vlr_cst_mat_dir*c_exp.qtde
                                            INTO v_vlr_custo
                                            FROM titens_custos
                                           WHERE itempr_id = c_exp.itempr_id;
                                       EXCEPTION
                                          WHEN NO_DATA_FOUND THEN
                                             v_vlr_custo := NULL;
                                       END;
                                    ELSE
                                       BEGIN
                                          SELECT vlr_cst_mat_dir*c_exp.qtde
                                            INTO v_vlr_custo
                                            FROM titens_custos_conf
                                           WHERE tmasc_item_id = c_exp.tmasc_item_id;
                                       EXCEPTION
                                          WHEN NO_DATA_FOUND THEN
                                             v_vlr_custo := NULL;
                                       END;
                                    END IF;

                                    INSERE_WG ( PI_ORDENACAO      => v_ordenacao
                                              , PI_NIVEL          => 3
                                              , PI_COD_ITEM       => v_cod_item
                                              , PI_DESCRICAO      => c_exp.descricao
                                              , PI_ITEMPR_ID      => c_exp.itempr_id
                                              , PI_TMASC_ITEM_ID  => c_exp.tmasc_item_id
                                              , PI_NUM_OPP        => c_exp.num_opp
                                              , PI_SETOR_SEQ      => c_exp.setor_seq
                                              , PI_QTDE           => c_exp.qtde      --Quantidade do item no pedido / Quantidade Agrupada do Pedido Necessario
                                              , PI_QTDE_SLDO      => c_exp.qtde_sldo --Quantidade do item pendente a faturar
                                              , PI_QTDE_A_AGRUPAR => NULL
                                              , PI_QTDE_AGRUPADA  => c_exp.qtde
                                              , PI_VLR_TOTAL_ORI  => NULL
                                              , PI_VLR_TOTAL      => ROUND(c_exp.vlr_total_alterado, 2)
                                              , PI_VLR_PEND       => NULL
                                              , PI_ITPDV_ID_NVL_1 => v_set(v_idx_set).itpdv_id
                                              , PI_ITPDV_ID_NVL_2 => c_vinc.itpdv_id
                                              , PI_ITPDV_ID_NVL_3 => c_exp.itpdv_id
                                              , PI_TIPO           => pi_tipo
                                              , PI_PDV_ID         => c_exp.pdv_id
                                              , PI_NUM_PEDIDO     => c_exp.num_pedido
                                              , PI_CUSTO_MEDIO    => ROUND(v_vlr_custo,2)
                                              , PI_ALTERADO       => NVL(c_exp.alterado,0)
                                              );
                                 END LOOP;
                              END LOOP;                           
                           END LOOP;
                        END LOOP;
                     END IF;
                  END LOOP;
                  v_set.delete;
               END LOOP;
            END IF;
         END LOOP;
         v_opp.delete;

      --Dados utilizados no programa FSULMAQ_COM008A (Bloco de Agrupamentos Realizados)
      ELSIF pi_tipo = 'AGRUPAMENTO' THEN
         OPEN c_cursor_opp FOR v_query_opp;
         LOOP
            FETCH c_cursor_opp BULK COLLECT INTO v_opp;
            IF v_opp.COUNT = 0 THEN
               EXIT;
            END IF;

            IF v_opp.COUNT > 0 THEN
               FOR v_idx_opp IN v_opp.FIRST..v_opp.LAST
               LOOP
                  v_query_set := ' SELECT itcm.cod_item                        cod_item
                                        /*, NVL(itpdv.descricao, itcm.descricao) descricao*/
                                        , SULMAQ_AGRUPA_ITENS.RETORNA_DESCRICAO_SULMAQ(itpdv.id, itpdv.tmasc_item_id) descricao
                                        , itempr.id                            itempr_id
                                        , itpdv.tmasc_item_id                  tmasc_item_id
                                        , sulmaq_agrupa_itens.retorna_mnemonico( itempr.id, itpdv.tmasc_item_id, ''SETOR_SEQ'' ) setor_seq
                                        , itpdv.qtde                           qtde
                                        , itpdv.qtde_sldo                      qtde_pend
                                        , itpdv.vlr_liq_ipi                    vlr_total
                                        , NULL                                 vlr_pend
                                        , itpdv.id                             itpdv_id
                                     FROM titens_pdv       itpdv
                                        , titens_comercial itcm
                                        , titens_empr      itempr
                                    WHERE itpdv.itcm_id   = itcm.id
                                      AND itcm.itempr_id  = itempr.id
                                      AND itpdv.qtde_canc < itpdv.qtde
                                      AND itpdv.pdv_id    = '||v_opp(v_idx_opp).pdv_id||' ';
         
                  IF pi_setor_seq IS NOT NULL THEN
                     v_query_set := v_query_set||' AND '||
                                 FOCCO3I_UTIL.INTERVALO( 'SULMAQ_AGRUPA_ITENS.RETORNA_MNEMONICO(itempr.id, itpdv.tmasc_item_id, ''SETOR_SEQ'') '
                                                       , pi_setor_seq
                                                       , 'A' );
                  END IF;

                  v_query_set := v_query_set||' ORDER BY setor_seq     ASC
                                                       , itcm.cod_item ASC ';
               
                  OPEN c_cursor_set FOR v_query_set;
                  LOOP
                     FETCH c_cursor_set BULK COLLECT INTO v_set;
                     IF v_set.COUNT = 0 THEN
                        EXIT;
                     END IF;

                     IF v_set.COUNT > 0 THEN
                        FOR v_idx_set IN v_set.FIRST..v_set.LAST
                        LOOP
                           ---------------------------------------------------------------------
                           ------------------------| PEDIDO NECESSARIO |------------------------
                           ------------------------|      2? NIVEL     |------------------------
                           ---------------------------------------------------------------------
                           FOR c_sul IN (SELECT sul.num_opp
                                              , sul.setor_seq
                                           FROM tsulmaq_vinc_pdv sul
                                              , titens_pdv       itpdv
                                          WHERE sul.itpdv_id = itpdv.id
                                            AND itpdv.id     = v_set(v_idx_set).itpdv_id)
                           LOOP
                              FOR c_vinc IN (SELECT itcm.cod_item                        cod_item
                                                  /*, NVL(itpdv.descricao, itcm.descricao) descricao*/
                                                  , SULMAQ_AGRUPA_ITENS.RETORNA_DESCRICAO_SULMAQ(itpdv.id, itpdv.tmasc_item_id) descricao
                                                  , itempr.id                            itempr_id
                                                  , itpdv.tmasc_item_id                  tmasc_item_id
                                                  , itpdv.qtde                           qtde
                                                  , sul.qtde                             qtde_agrupada
                                                  , sul.num_opp                          num_opp
                                                  , sul.setor_seq                        setor_seq
                                                  , itpdv.id                             itpdv_id
                                                  , pdv.id                               pdv_id
                                                  , pdv.num_pedido                       num_pedido
                                                  , itpdv.qtde-sul.qtde                  qtde_sldo
                                                  , itpdv.vlr_liq_ipi                    vlr_total
                                               FROM tsulmaq_vinc_pdv      sul
                                                  , sdi_orcfocco_oportcrm opp
                                                  , tpedidos_venda        pdv
                                                  , titens_pdv            itpdv
                                                  , titens_comercial      itcm
                                                  , titens_empr           itempr
                                              WHERE sul.num_opp           = opp.num_opp
                                                AND sul.setor_seq         = sulmaq_agrupa_itens.retorna_mnemonico(itempr.ID, itpdv.tmasc_item_id, 'SETOR_SEQ')
                                                AND opp.id_tpedidos_venda = pdv.ID
                                                AND pdv.ID                = itpdv.pdv_id
                                                AND itpdv.itcm_id         = itcm.ID
                                                AND itcm.itempr_id        = itempr.ID
                                                AND pdv.tipo              = 'PDV'
                                                AND opp.revisao           = (SELECT MAX(opp2.revisao)
                                                                               FROM sdi_orcfocco_oportcrm opp2
                                                                                  , tpedidos_venda pdv2
                                                                              WHERE pdv2.ID      = opp2.id_tpedidos_venda
                                                                                AND opp2.num_opp = opp.num_opp
                                                                                AND pdv2.tipo    = pdv.tipo)
                                                AND sul.num_opp           = c_sul.num_opp
                                                AND sul.setor_seq         = c_sul.setor_seq
                                                AND sul.itpdv_id          = v_set(v_idx_set).itpdv_id)
                              LOOP
                                 INC(v_ordenacao);

                                 IF pi_identa = 1 THEN
                                    v_cod_item := LPAD(' ',10,' ')||c_vinc.cod_item;
                                 ELSE
                                    v_cod_item := c_vinc.cod_item;
                                 END IF;

                                 INSERE_WG ( PI_ORDENACAO      => v_ordenacao
                                           , PI_NIVEL          => 2
                                           , PI_COD_ITEM       => v_cod_item
                                           , PI_DESCRICAO      => c_vinc.descricao
                                           , PI_ITEMPR_ID      => c_vinc.itempr_id
                                           , PI_TMASC_ITEM_ID  => c_vinc.tmasc_item_id
                                           , PI_NUM_OPP        => c_vinc.num_opp
                                           , PI_SETOR_SEQ      => c_vinc.setor_seq
                                           , PI_QTDE           => c_vinc.qtde          --Quantidade do Item no Pedido
                                           , PI_QTDE_SLDO      => NULL                 --Quantidade Pendente
                                           , PI_QTDE_A_AGRUPAR => NULL
                                           , PI_QTDE_AGRUPADA  => c_vinc.qtde_agrupada --Quantidade Agrupada do Item
                                           , PI_VLR_TOTAL_ORI  => NULL--c_vinc.vlr_total
                                           , PI_VLR_TOTAL      => NULL--c_vinc.vlr_total
                                           , PI_VLR_PEND       => NULL
                                           , PI_ITPDV_ID_NVL_1 => v_set(v_idx_set).itpdv_id
                                           , PI_ITPDV_ID_NVL_2 => c_vinc.itpdv_id
                                           , PI_ITPDV_ID_NVL_3 => NULL
                                           , PI_TIPO           => pi_tipo
                                           , PI_PDV_ID         => c_vinc.pdv_id
                                           , PI_NUM_PEDIDO     => c_vinc.num_pedido
                                           , PI_CUSTO_MEDIO    => NULL
                                           , PI_ALTERADO       => 0
                                           );

                                 -------------------------------------------------------------------
                                 -----------------------| PEDIDO EXPEDIC?O  |-----------------------
                                 -----------------------|     3? NIVEL      |-----------------------
                                 -------------------------------------------------------------------
                                 FOR c_exp IN ( SELECT itcm.cod_item                        cod_item
                                                     , NVL(itpdv.descricao, itcm.descricao) descricao
                                                     , itempr.id                            itempr_id
                                                     , itpdv.tmasc_item_id                  tmasc_item_id
                                                     --, ((itpdv.qtde/c_vinc.qtde)*NVL(c_vinc.qtde_agrupada,1)) qtde                 -- Comentado  Sol. 295114
                                                     , (((itpdv.qtde-itpdv.qtde_canc) / greatest(nvl(c_vinc.qtde,1),1))*NVL(c_vinc.qtde_agrupada,1)) qtde -- Adicionado Sol. 295114
                                                     , itpdv.qtde_sldo                      qtde_sldo
                                                     , fab.oportunidade                     num_opp
                                                     , fab.setor_seq                        setor_seq
                                                     , itpdv.id                             itpdv_id
                                                     , pdv.id                               pdv_id
                                                     , pdv.num_pedido                       num_pedido
                                                     , itpdv.qtde_atend                     qtde_faturada
                                                     , fab.alterado                         alterado
                                                     , fab.vlr_total                        vlr_total_alterado
                                                  FROM sdi_pdv_expedicao     exp
                                                     , tpedidos_venda        pdv
                                                     , titens_pdv            itpdv
                                                     , sdi_listas_fabricacao fab
                                                     , titens_comercial      itcm
                                                     , titens_empr           itempr
                                                 WHERE exp.pdv_id     = pdv.id
                                                   AND pdv.id         = itpdv.pdv_id
                                                   AND itpdv.id       = fab.itpdv_id
                                                   AND itpdv.itcm_id  = itcm.id
                                                   AND itcm.itempr_id = itempr.id
                                                   AND itpdv.qtde_canc < itpdv.qtde
                                                   AND pdv.tipo       = 'PDV'
                                                   AND exp.num_opp    = c_vinc.num_opp
                                                   AND fab.setor_seq  = c_vinc.setor_seq )
                                 LOOP
                                    INC(v_ordenacao);

                                    IF pi_identa = 1 THEN
                                       v_cod_item := LPAD(' ',20,' ')||c_exp.cod_item;
                                    ELSE
                                       v_cod_item := LPAD(' ',10,' ')||c_exp.cod_item;
                                    END IF;

                                    IF c_exp.tmasc_item_id IS NULL THEN
                                       BEGIN
                                          SELECT vlr_cst_mat_dir*c_exp.qtde
                                            INTO v_vlr_custo
                                            FROM titens_custos
                                           WHERE itempr_id = c_exp.itempr_id;
                                       EXCEPTION
                                          WHEN NO_DATA_FOUND THEN
                                             v_vlr_custo := NULL;
                                       END;
                                    ELSE
                                       BEGIN
                                          SELECT vlr_cst_mat_dir*c_exp.qtde
                                            INTO v_vlr_custo
                                            FROM titens_custos_conf
                                           WHERE tmasc_item_id = c_exp.tmasc_item_id;
                                       EXCEPTION
                                          WHEN NO_DATA_FOUND THEN
                                             v_vlr_custo := NULL;
                                       END;
                                    END IF;

                                    INSERE_WG ( PI_ORDENACAO      => v_ordenacao
                                              , PI_NIVEL          => 3
                                              , PI_COD_ITEM       => v_cod_item
                                              , PI_DESCRICAO      => c_exp.descricao
                                              , PI_ITEMPR_ID      => c_exp.itempr_id
                                              , PI_TMASC_ITEM_ID  => c_exp.tmasc_item_id
                                              , PI_NUM_OPP        => c_exp.num_opp
                                              , PI_SETOR_SEQ      => c_exp.setor_seq
                                              , PI_QTDE           => c_exp.qtde      --Quantidade do item no pedido / Quantidade Agrupada do Pedido Necessario
                                              , PI_QTDE_SLDO      => NULL
                                              , PI_QTDE_A_AGRUPAR => NULL
                                              , PI_QTDE_AGRUPADA  => c_exp.qtde      --Quantidade do item no pedido / Quantidade Agrupada do Pedido Necessario
                                              , PI_VLR_TOTAL_ORI  => NULL
                                              , PI_VLR_TOTAL      => ROUND(c_exp.vlr_total_alterado,2)--NULL
                                              , PI_VLR_PEND       => NULL
                                              , PI_ITPDV_ID_NVL_1 => v_set(v_idx_set).itpdv_id
                                              , PI_ITPDV_ID_NVL_2 => c_vinc.itpdv_id
                                              , PI_ITPDV_ID_NVL_3 => c_exp.itpdv_id
                                              , PI_TIPO           => pi_tipo
                                              , PI_PDV_ID         => c_exp.pdv_id
                                              , PI_NUM_PEDIDO     => c_exp.num_pedido
                                              , PI_CUSTO_MEDIO    => ROUND(v_vlr_custo,2)
                                              , PI_ALTERADO       => NVL(c_exp.alterado,0)
                                              );
                                 END LOOP;
                              END LOOP;
                           END LOOP;
                        END LOOP;
                     END IF;
                  END LOOP;
                  v_set.delete;
               END LOOP;
            END IF;
         END LOOP;
         v_opp.delete;

      --Dados utilizados no programa FSULMAQ_COM008A (Bloco de Agrupamentos Pendentes)
      ELSIF pi_tipo = 'PENDENTES' THEN
         v_query := ' SELECT itcm.cod_item                        cod_item
                           /*, NVL(itpdv.descricao, itcm.descricao) descricao*/
                           , SULMAQ_AGRUPA_ITENS.RETORNA_DESCRICAO_SULMAQ(itpdv.id, itpdv.tmasc_item_id) descricao
                           , itempr.id                            itempr_id
                           , itpdv.tmasc_item_id                  tmasc_item_id
                           , opp.num_opp                          num_opp
                           , SULMAQ_AGRUPA_ITENS.RETORNA_MNEMONICO(itempr.id, itpdv.tmasc_item_id, ''SETOR_SEQ'') setor_seq
                           , itpdv.qtde                           qtde
                           , 0                                    vlr_total
                           , 0                                    vlr_pend
                           , itpdv.id                             itpdv_id
                           , pdv.id                               pdv_id
                           , pdv.num_pedido                       num_pedido
                        FROM sdi_orcfocco_oportcrm opp
                           , tpedidos_venda        pdv
                           , titens_pdv            itpdv
                           , titens_comercial      itcm
                           , titens_empr           itempr
                       WHERE opp.id_tpedidos_venda = pdv.id
                         AND pdv.id                = itpdv.pdv_id
                         AND itpdv.itcm_id         = itcm.id
                         AND itcm.itempr_id        = itempr.id
                         AND pdv.tipo              = ''PDV''
                         AND opp.revisao = (SELECT MAX(opp2.revisao)
                                              FROM sdi_orcfocco_oportcrm opp2
                                                 , tpedidos_venda        pdv2
                                             WHERE pdv2.id      = opp2.id_tpedidos_venda
                                               AND opp2.num_opp = opp.num_opp
                                               AND pdv2.tipo    = pdv.tipo)
                         AND itpdv.qtde_canc < itpdv.qtde ';

         v_query := v_query || ' AND ' || FOCCO3I_UTIL.INTERVALO('opp.num_opp', pi_num_opp, 'N');

         IF v_descon_itens IS NOT NULL THEN
            v_query := v_query || ' AND INSTR( '',''||'''||v_descon_itens||'''||'','', '',''||itcm.cod_item||'','', 1 ) = 0 ';
         END IF;

         IF pi_setor_seq IS NOT NULL THEN
            v_query := v_query || ' AND ' ||
                       FOCCO3I_UTIL.INTERVALO('SULMAQ_AGRUPA_ITENS.RETORNA_MNEMONICO(itempr.id, itpdv.tmasc_item_id, ''SETOR_SEQ'') '
                                             , pi_setor_seq
                                             , 'A');
         END IF;

         v_query := v_query || ' ORDER BY num_opp
                                        , setor_seq     ASC
                                        , itcm.cod_item ASC ';

         OPEN c_cursor FOR v_query;
         LOOP
            FETCH c_cursor BULK COLLECT INTO v_reg2;
            IF v_reg2.COUNT = 0 THEN
               EXIT;
            END IF;

            IF v_reg2.COUNT > 0 THEN
               FOR v_idx2 IN v_reg2.FIRST..v_reg2.LAST
               LOOP
                  INC(v_ordenacao);

                  BEGIN
                     SELECT SUM(qtde)
                       INTO v_qtde_agrupada
                       FROM tsulmaq_vinc_pdv
                      WHERE num_opp   = v_reg2(v_idx2).num_opp
                        AND setor_seq = v_reg2(v_idx2).setor_seq;
                  EXCEPTION
                     WHEN NO_DATA_FOUND THEN
                        v_qtde_agrupada := NULL;
                  END;

                  INSERE_WG ( PI_ORDENACAO      => v_ordenacao
                            , PI_NIVEL          => 2
                            , PI_COD_ITEM       => v_reg2(v_idx2).cod_item
                            , PI_DESCRICAO      => v_reg2(v_idx2).descricao
                            , PI_ITEMPR_ID      => v_reg2(v_idx2).itempr_id
                            , PI_TMASC_ITEM_ID  => v_reg2(v_idx2).tmasc_item_id
                            , PI_NUM_OPP        => v_reg2(v_idx2).num_opp
                            , PI_SETOR_SEQ      => v_reg2(v_idx2).setor_seq
                            , PI_QTDE           => v_reg2(v_idx2).qtde         --Quantidade do Item no Pedido
                            , PI_QTDE_SLDO      => NULL
                            , PI_QTDE_A_AGRUPAR => NULL                        --Quantidade a agrupar (calculado quando marcar o check-box)
                            , PI_QTDE_AGRUPADA  => NVL(v_qtde_agrupada,0)      --Quantidade Agrupada
                            , PI_VLR_TOTAL_ORI  => ROUND(v_reg2(v_idx2).vlr_total,2)
                            , PI_VLR_TOTAL      => ROUND(v_reg2(v_idx2).vlr_total,2)
                            , PI_VLR_PEND       => ROUND(v_reg2(v_idx2).vlr_pend,2)
                            , PI_ITPDV_ID_NVL_1 => NULL
                            , PI_ITPDV_ID_NVL_2 => v_reg2(v_idx2).itpdv_id--NULL
                            , PI_ITPDV_ID_NVL_3 => NULL
                            , PI_TIPO           => pi_tipo
                            , PI_PDV_ID         => v_reg2(v_idx2).pdv_id
                            , PI_NUM_PEDIDO     => v_reg2(v_idx2).num_pedido
                            , PI_CUSTO_MEDIO    => NULL
                            , PI_ALTERADO       => 0
                            );

                  -------------------------------------------------------------------
                  -----------------------| PEDIDO EXPEDIC?O  |-----------------------
                  -----------------------|     3? NIVEL      |-----------------------
                  -------------------------------------------------------------------
                  FOR c_exp IN ( SELECT itcm.cod_item                        cod_item
                                      , NVL(itpdv.descricao, itcm.descricao) descricao
                                      , itempr.id                            itempr_id
                                      , itpdv.tmasc_item_id                  tmasc_item_id
                                      , (itpdv.qtde/ greatest(NVL(v_qtde_agrupada,1),1))  qtde
                                      , itpdv.qtde_sldo                      qtde_sldo
                                      , fab.oportunidade                     num_opp
                                      , fab.setor_seq                        setor_seq
                                      , itpdv.id                             itpdv_id
                                      , pdv.id                               pdv_id
                                      , pdv.num_pedido                       num_pedido
                                      , itpdv.qtde_atend                     qtde_faturada
                                      , fab.alterado                         alterado
                                      , fab.vlr_total                        vlr_total_alterado
                                   FROM sdi_pdv_expedicao     exp
                                      , tpedidos_venda        pdv
                                      , titens_pdv            itpdv
                                      , sdi_listas_fabricacao fab
                                      , titens_comercial      itcm
                                      , titens_empr           itempr
                                  WHERE exp.pdv_id     = pdv.id
                                    AND pdv.id         = itpdv.pdv_id
                                    AND itpdv.id       = fab.itpdv_id
                                    AND itpdv.itcm_id  = itcm.id
                                    AND itcm.itempr_id = itempr.id
                                    AND itpdv.qtde_canc < itpdv.qtde
                                    AND pdv.tipo       = 'PDV'
                                    AND exp.num_opp    = v_reg2(v_idx2).num_opp--c_vinc.num_opp
                                    AND fab.setor_seq  = v_reg2(v_idx2).setor_seq ) --c_vinc.setor_seq )
                  LOOP
                     INC(v_ordenacao);

                     IF pi_identa = 1 THEN
                        v_cod_item := LPAD(' ',20,' ')||c_exp.cod_item;
                     ELSE
                        v_cod_item := LPAD(' ',10,' ')||c_exp.cod_item;
                     END IF;

                     IF c_exp.tmasc_item_id IS NULL THEN
                        BEGIN
                           SELECT vlr_cst_mat_dir*c_exp.qtde
                             INTO v_vlr_custo
                             FROM titens_custos
                            WHERE itempr_id = c_exp.itempr_id;
                        EXCEPTION
                           WHEN NO_DATA_FOUND THEN
                              v_vlr_custo := NULL;
                        END;
                     ELSE
                        BEGIN
                           SELECT vlr_cst_mat_dir*c_exp.qtde
                             INTO v_vlr_custo
                             FROM titens_custos_conf
                            WHERE tmasc_item_id = c_exp.tmasc_item_id;
                        EXCEPTION
                           WHEN NO_DATA_FOUND THEN
                              v_vlr_custo := NULL;
                        END;
                     END IF;

                     INSERE_WG ( PI_ORDENACAO      => v_ordenacao
                               , PI_NIVEL          => 3
                               , PI_COD_ITEM       => v_cod_item
                               , PI_DESCRICAO      => c_exp.descricao
                               , PI_ITEMPR_ID      => c_exp.itempr_id
                               , PI_TMASC_ITEM_ID  => c_exp.tmasc_item_id
                               , PI_NUM_OPP        => c_exp.num_opp
                               , PI_SETOR_SEQ      => c_exp.setor_seq
                               , PI_QTDE           => c_exp.qtde      --Quantidade do item no pedido / Quantidade Agrupada do Pedido Necessario
                               , PI_QTDE_SLDO      => NULL
                               , PI_QTDE_A_AGRUPAR => NULL
                               , PI_QTDE_AGRUPADA  => c_exp.qtde      --Quantidade do item no pedido / Quantidade Agrupada do Pedido Necessario
                               , PI_VLR_TOTAL_ORI  => NULL
                               , PI_VLR_TOTAL      => NULL
                               , PI_VLR_PEND       => NULL
                               , PI_ITPDV_ID_NVL_1 => NULL
                               , PI_ITPDV_ID_NVL_2 => v_reg2(v_idx2).itpdv_id
                               , PI_ITPDV_ID_NVL_3 => c_exp.itpdv_id
                               , PI_TIPO           => pi_tipo
                               , PI_PDV_ID         => c_exp.pdv_id
                               , PI_NUM_PEDIDO     => c_exp.num_pedido
                               , PI_CUSTO_MEDIO    => ROUND(v_vlr_custo,2)
                               , PI_ALTERADO       => NVL(c_exp.alterado,0)
                               );
                  END LOOP;
               END LOOP;
            END IF;
         END LOOP;
      END IF;
      v_reg2.delete;
      
   END INSERE_WG_FSULMAQ_COM008;
   
   PROCEDURE REALIZA_AGRUPAMENTO ( pi_itpdv_id IN titens_pdv.id%TYPE ) IS
   
      v_existe NUMBER(1);
   
   BEGIN
      FOR c_agrup IN ( SELECT *
                         FROM wg_fsulmaq_com008
                        WHERE tipo        = 'PENDENTES'
                          AND selecionado = 1 )
      LOOP
         BEGIN
            SELECT 1
              INTO v_existe
              FROM tsulmaq_vinc_pdv
             WHERE num_opp   = c_agrup.num_opp
               AND setor_seq = c_agrup.setor_seq
               AND itpdv_id  = pi_itpdv_id;
         EXCEPTION
            WHEN NO_DATA_FOUND THEN
               v_existe := 0;
         END;

         IF v_existe = 1 THEN
            UPDATE tsulmaq_vinc_pdv
               SET qtde = qtde+c_agrup.qtde_a_agrupar
             WHERE num_opp   = c_agrup.num_opp
               AND setor_seq = c_agrup.setor_seq
               AND itpdv_id  = pi_itpdv_id;
               
         ELSE
            BEGIN
               INSERT INTO tsulmaq_vinc_pdv
                         ( id
                         , dt_sist
                         , usuario
                         , itpdv_id
                         , num_opp
                         , setor_seq
                         , qtde
                         , valor
                         )
                  VALUES ( seq_id_tsulmaq_vinc_pdv.NEXTVAL
                         , SYSDATE
                         , FOCCO3I_UTIL.RETORNA_USUARIO
                         , pi_itpdv_id
                         , c_agrup.num_opp
                         , c_agrup.setor_seq
                         , c_agrup.qtde_a_agrupar
                         , 0 --mudar depois
                         );
            END;
         END IF;
      END LOOP;

      --Este update desmarca os itens na tela FSULMAQ_COM008A depois de realizar o agrupamento
      UPDATE wg_fsulmaq_com008
         SET selecionado = 0
--           , onde = DBMS_UTILITY.format_call_stack
       WHERE tipo        = 'CONSULTA'
         AND selecionado = 1
         AND nivel > 1;

   END REALIZA_AGRUPAMENTO;
   
   PROCEDURE REALIZA_EXCLUSAO IS
   
   BEGIN
      FOR c_del IN ( SELECT *
                       FROM wg_fsulmaq_com008
                      WHERE nivel > 1
                        AND tipo        = 'AGRUPAMENTO'
                        AND EXISTS (SELECT 1
                                      FROM tsulmaq_vinc_pdv
                                     WHERE itpdv_id = wg_fsulmaq_com008.itpdv_id_nvl_1)
                        AND selecionado = 1 )
      LOOP
         DELETE tsulmaq_vinc_pdv
          WHERE itpdv_id  = c_del.itpdv_id_nvl_1
            AND num_opp   = c_del.num_opp
            AND setor_seq = c_del.setor_seq;
            
         FOR nivel_3 IN ( SELECT *
                            FROM wg_fsulmaq_com008
                           WHERE tipo           = c_del.tipo
                             AND itpdv_id_nvl_2 = c_del.itpdv_id_nvl_2
                             AND itpdv_id_nvl_3 IS NOT NULL )
         LOOP
            UPDATE sdi_listas_fabricacao
               SET vlr_total = NULL
                 , alterado  = NULL
             WHERE setor_seq    = nivel_3.setor_seq
               AND oportunidade = nivel_3.num_opp
               AND itpdv_id     = nivel_3.itpdv_id_nvl_3;
         END LOOP;
      END LOOP;
   END REALIZA_EXCLUSAO;
   
   PROCEDURE RECALCULA_VALORES_TELA ( pi_itpdv_id  IN wg_fsulmaq_com008.itpdv_id_nvl_1%TYPE
                                    , pi_tipo      IN VARCHAR2
                                    , pi_considera IN NUMBER
                                    , po_erro     OUT VARCHAR2 ) IS 
      v_custo_medio         wg_fsulmaq_com008.custo_medio%TYPE;
      v_sum_custo_medio     wg_fsulmaq_com008.custo_medio%TYPE;
      v_perc_abs            wg_fsulmaq_com008.perc_abs%TYPE;
      v_vlr_total           wg_fsulmaq_com008.vlr_total%TYPE;
      v_vlr_total_ori       wg_fsulmaq_com008.vlr_total%TYPE;
      v_vlr_total_exp       wg_fsulmaq_com008.vlr_total%TYPE;
      v_soma                wg_fsulmaq_com008.vlr_total%TYPE;
      v_existe_alterado     BOOLEAN := FALSE;
      v_sum_custo_medio_alt wg_fsulmaq_com008.custo_medio%TYPE;
      v_new_vlr             wg_fsulmaq_com008.vlr_total%TYPE;
      v_count               NUMBER;
      v_erro                VARCHAR2(4000);
      v_soma_perc_abs       wg_fsulmaq_com008.perc_abs%TYPE;
      v_soma_vlr_total      wg_fsulmaq_com008.vlr_total%TYPE;
      v_vlr_total_alt       wg_fsulmaq_com008.vlr_total%TYPE;
      v_diferenca           wg_fsulmaq_com008.perc_abs%TYPE;
      v_controle            NUMBER(1);
      v_existe              NUMBER(1);

      PROCEDURE VALIDA_VALORES (po_erro OUT VARCHAR2) IS
         v_soma            wg_fsulmaq_com008.vlr_total%TYPE;
         v_todos_alterados NUMBER(1);
      BEGIN
         FOR nivel_2 IN ( SELECT DISTINCT itpdv_id_nvl_2
                               , TRIM(cod_item) cod_item
                               , ROUND(vlr_total,2) vlr_total
                            FROM wg_fsulmaq_com008
                           WHERE itpdv_id_nvl_1 = pi_itpdv_id
                             AND nivel          = 2
                             AND tipo           = pi_tipo )
         LOOP
            BEGIN
               SELECT 0
                 INTO v_todos_alterados
                 FROM wg_fsulmaq_com008
                WHERE itpdv_id_nvl_2 = nivel_2.itpdv_id_nvl_2
                  AND itpdv_id_nvl_1 = pi_itpdv_id
                  AND nivel          = 3
                  AND tipo           = pi_tipo
                  AND alterado       = 0
                  AND ROWNUM         = 1;
            EXCEPTION
               WHEN NO_DATA_FOUND THEN
                  v_todos_alterados := 1;
            END;

            BEGIN
               SELECT ROUND(SUM(vlr_total),2)
                 INTO v_soma
                 FROM wg_fsulmaq_com008
                WHERE itpdv_id_nvl_2 = nivel_2.itpdv_id_nvl_2
                  AND itpdv_id_nvl_1 = pi_itpdv_id
                  AND nivel          = 3
                  AND tipo           = pi_tipo
                  AND alterado       = 1;
            EXCEPTION
               WHEN NO_DATA_FOUND THEN
                  v_soma     := NULL;
            END;

            IF v_todos_alterados = 0 THEN
               IF v_soma > nivel_2.vlr_total THEN
                  po_erro := 'A soma dos itens alterados ('||TO_CHAR(v_soma,'FM999G999G990D00')||') excede o valor do item necessario ('||
                  TO_CHAR(nivel_2.vlr_total,'FM999G999G990D00')||'). Item: '||nivel_2.cod_item||'. Verifique!';
                  EXIT;
               END IF;
            ELSE
               IF v_soma > nivel_2.vlr_total THEN
                  po_erro := 'A soma dos itens alterados ('||TO_CHAR(v_soma,'FM999G999G990D00')||') excede o valor do item necessario ('||
                  TO_CHAR(nivel_2.vlr_total,'FM999G999G990D00')||'). Item: '||nivel_2.cod_item||'. Verifique!';
                  EXIT;
               ELSIF v_soma < nivel_2.vlr_total THEN
                  po_erro := 'A soma dos itens alterados ('||TO_CHAR(v_soma,'FM999G999G990D00')||') e menor que o valor do item necessario ('||
                  TO_CHAR(nivel_2.vlr_total,'FM999G999G990D00')||'). Item: '||nivel_2.cod_item||'. Verifique!';
                  EXIT;
               END IF;
            END IF;
         END LOOP;
      END VALIDA_VALORES;

      PROCEDURE ARREDONDA_VALORES ( pi_vlr_ori        IN NUMBER
                                  , pi_vlr_des        IN NUMBER
                                  , pi_campo          IN VARCHAR2
                                  , pi_nivel          IN NUMBER
                                  , pi_tipo           IN VARCHAR2
                                  , pi_alterado       IN NUMBER
                                  , pi_itpdv_id_nvl_1 IN wg_fsulmaq_com008.itpdv_id_nvl_1%TYPE
                                  , pi_itpdv_id_nvl_2 IN wg_fsulmaq_com008.itpdv_id_nvl_2%TYPE
                                  , pi_itpdv_id_nvl_3 IN wg_fsulmaq_com008.itpdv_id_nvl_3%TYPE ) IS

         v_diferenca           NUMBER(17,8);
         v_controle            NUMBER(1);
      BEGIN
       
         IF pi_vlr_ori <> pi_vlr_des THEN
            v_diferenca := ABS(pi_vlr_ori-pi_vlr_des);

            IF pi_vlr_ori < pi_vlr_des THEN
               v_controle := 0; --Soma
            ELSE
               v_controle := 1; --Subtrai
            END IF;
            
            UPDATE wg_fsulmaq_com008
               SET perc_abs  = DECODE(pi_campo, 'PERC_ABS' , DECODE(v_controle, 0, (perc_abs+v_diferenca) , (perc_abs-v_diferenca)) , perc_abs)
                 , vlr_total = DECODE(pi_campo, 'VLR_TOTAL', DECODE(v_controle, 0, (vlr_total+v_diferenca), (vlr_total-v_diferenca)), vlr_total)
--                 , onde = DBMS_UTILITY.format_call_stack
             WHERE NVL(itpdv_id_nvl_1, 0) = NVL(NVL(pi_itpdv_id_nvl_1, itpdv_id_nvl_1), 0)
               AND NVL(itpdv_id_nvl_2, 0) = NVL(NVL(pi_itpdv_id_nvl_2, itpdv_id_nvl_2), 0)
               AND NVL(itpdv_id_nvl_3, 0) = NVL(NVL(pi_itpdv_id_nvl_3, itpdv_id_nvl_3), 0)
               AND nivel                  = pi_nivel
               AND tipo                   = pi_tipo
               AND alterado               = 0
               AND NVL(alterado, 0)       = NVL(pi_alterado, NVL(alterado, 0)) -- Sol. 293361
               AND NOT EXISTS(SELECT 1
                                FROM THIST_MOV_ITE_PDV HIST
                              WHERE HIST.ITPDV_ID = wg_fsulmaq_com008.Itpdv_id_nvl_3
                                AND HIST.ITNFS_ID IS NOT NULL)
               AND DECODE ( pi_campo
                          , 'PERC_ABS'
                          , perc_abs
                          , 'VLR_TOTAL'
                          , vlr_total ) = (SELECT DECODE ( pi_campo
                                                         , 'PERC_ABS'
                                                         , MAX(perc_abs)
                                                         , 'VLR_TOTAL'
                                                         , MAX(vlr_total) )
                                             FROM wg_fsulmaq_com008
                                            WHERE NVL(itpdv_id_nvl_1, 0) = NVL(NVL(pi_itpdv_id_nvl_1, itpdv_id_nvl_1), 0)
                                              AND NVL(itpdv_id_nvl_2, 0) = NVL(NVL(pi_itpdv_id_nvl_2, itpdv_id_nvl_2), 0)
                                              AND NVL(itpdv_id_nvl_3, 0) = NVL(NVL(pi_itpdv_id_nvl_3, itpdv_id_nvl_3), 0)
                                              AND nivel            = pi_nivel
                                              AND tipo             = pi_tipo
                                              AND NVL(alterado, 0) = NVL(pi_alterado, NVL(alterado, 0))-- Sol. 293361
                                              ) 
               AND ROWNUM         = 1;
         END IF;
      END ARREDONDA_VALORES;

      PROCEDURE CALCULA_CUSTOS IS
      BEGIN
         /*******************************/
         /* 1? Nivel -> Pedido Faturado */
         /*******************************/
         FOR nivel_1 IN ( SELECT *
                            FROM wg_fsulmaq_com008
                           WHERE itpdv_id_nvl_1 = pi_itpdv_id
                             AND pi_tipo        = pi_tipo
                             AND nivel          = 1 )
         LOOP
            /*********************************/
            /* 2? Nivel -> Pedido Necessario */
            /*********************************/
            FOR nivel_2 IN ( SELECT *
                               FROM wg_fsulmaq_com008
                              WHERE itpdv_id_nvl_1 = nivel_1.itpdv_id_nvl_1
                                AND nivel          = 2
                                AND tipo           = pi_tipo )
            LOOP
               --Calcula o custo do item de 2? Nivel
               BEGIN
                  SELECT ROUND(SUM(custo_medio),2)
                    INTO v_custo_medio
                    FROM wg_fsulmaq_com008
                   WHERE itpdv_id_nvl_1 = nivel_2.itpdv_id_nvl_1
                     AND itpdv_id_nvl_2 = nivel_2.itpdv_id_nvl_2
                     AND nivel          = 3
                     AND tipo           = pi_tipo;
               EXCEPTION
                  WHEN NO_DATA_FOUND THEN
                     v_custo_medio := NULL;
               END;
              
               UPDATE wg_fsulmaq_com008
                  SET custo_medio = NVL(v_custo_medio, 0)
--                    , onde = DBMS_UTILITY.format_call_stack
                WHERE itpdv_id_nvl_1 = nivel_2.itpdv_id_nvl_1
                  AND itpdv_id_nvl_2 = nivel_2.itpdv_id_nvl_2
                  AND nivel          = 2
                  AND tipo           = pi_tipo;

               v_soma_perc_abs := 0;
               /********************************/
               /* 3? Nivel -> Pedido Expedic?o */
               /********************************/
               FOR nivel_3 IN ( SELECT *
                                  FROM wg_fsulmaq_com008
                                 WHERE itpdv_id_nvl_1 = nivel_2.itpdv_id_nvl_1
                                   AND itpdv_id_nvl_2 = nivel_2.itpdv_id_nvl_2
                                   AND nivel          = 3
                                   AND tipo           = pi_tipo )
               LOOP
                  --Calcula o Percentual de Absorc?o dos Itens de 3? Nivel
                  v_perc_abs      := ROUND(((nivel_3.custo_medio*100)/ greatest(NVL(v_custo_medio,1),1)  ),2);
                  v_soma_perc_abs := v_soma_perc_abs+v_perc_abs;

                  UPDATE wg_fsulmaq_com008
                     SET perc_abs = v_perc_abs
--                     , onde = DBMS_UTILITY.format_call_stack
                   WHERE itpdv_id_nvl_1 = nivel_3.itpdv_id_nvl_1
                     AND itpdv_id_nvl_2 = nivel_3.itpdv_id_nvl_2
                     AND itpdv_id_nvl_3 = nivel_3.itpdv_id_nvl_3
                     AND nivel          = 3
                     AND tipo           = pi_tipo;
               END LOOP;

               /*####################################################################*/
               /*# Arredondamento de valores dos percentuais de absorc?o (3? nivel) #*/
               /*####################################################################*/
               IF v_soma_perc_abs <> 100 THEN
                  ARREDONDA_VALORES ( pi_vlr_ori       =>  v_soma_perc_abs
                                    , pi_vlr_des       =>  100
                                    , pi_campo         =>  'PERC_ABS'
                                    , pi_nivel         =>  3
                                    , pi_tipo          =>  pi_tipo
                                    , pi_alterado      =>  0--NULL -- Sol. 293361
                                    , pi_itpdv_id_nvl_1=>  nivel_2.itpdv_id_nvl_1
                                    , pi_itpdv_id_nvl_2=>  nivel_2.itpdv_id_nvl_2
                                    , pi_itpdv_id_nvl_3=>  NULL
                                    );
               END IF;
               /*####################################################################*/
            END LOOP;

            --Busca a soma do custo medio de todos os 2?'s niveis!
            BEGIN
               SELECT ROUND(SUM(NVL(custo_medio, 0)),2)
                 INTO v_sum_custo_medio
                 FROM wg_fsulmaq_com008
                WHERE itpdv_id_nvl_1 = nivel_1.itpdv_id_nvl_1
                  AND nivel          = 2
                  AND tipo           = pi_tipo;
            EXCEPTION
               WHEN NO_DATA_FOUND THEN
                  v_sum_custo_medio := NULL;
            END;

            v_soma_perc_abs := 0;
            /*********************************/
            /* 2? Nivel -> Pedido Necessario */
            /*********************************/
            FOR nivel_2 IN ( SELECT *
                               FROM wg_fsulmaq_com008
                              WHERE itpdv_id_nvl_1 = nivel_1.itpdv_id_nvl_1
                                AND nivel          = 2
                                AND tipo           = pi_tipo )
            LOOP
               --v_perc_abs      := ROUND(((NVL(nivel_2.custo_medio, 0)*100)/NVL(v_sum_custo_medio, 0)),2);            -- Comentado  Sol. 295260
               v_perc_abs      := ROUND(((NVL(nivel_2.custo_medio, 0)*100)/GREATEST(NVL(v_sum_custo_medio, 1), 1)),2); -- Adicionado Sol. 295260

               v_soma_perc_abs := NVL(v_soma_perc_abs, 0)+NVL(v_perc_abs, 0);

               UPDATE wg_fsulmaq_com008
                  SET perc_abs = v_perc_abs
--                  , onde = DBMS_UTILITY.format_call_stack
                WHERE itpdv_id_nvl_1 = nivel_2.itpdv_id_nvl_1
                  AND itpdv_id_nvl_2 = nivel_2.itpdv_id_nvl_2
                  AND nivel          = 2
                  AND tipo           = pi_tipo;
            END LOOP;

            /*####################################################################*/
            /*# Arredondamento de valores dos percentuais de absorc?o (2? nivel) #*/
            /*####################################################################*/
            IF v_soma_perc_abs <> 100 THEN
               ARREDONDA_VALORES ( pi_vlr_ori       => v_soma_perc_abs
                                 , pi_vlr_des       => 100
                                 , pi_campo         => 'PERC_ABS'
                                 , pi_nivel         => 2
                                 , pi_tipo          => pi_tipo
                                 , pi_alterado      => 0--NULL -- Sol. 293361
                                 , pi_itpdv_id_nvl_1=> nivel_1.itpdv_id_nvl_1
                                 , pi_itpdv_id_nvl_2=> NULL
                                 , pi_itpdv_id_nvl_3=> NULL
                                 );
            END IF;
            /*####################################################################*/
         END LOOP;
      END CALCULA_CUSTOS;
   
      PROCEDURE CALCULA_VALORES IS
         v_aux      NUMBER;
         v_controle NUMBER;
         v_dif      NUMBER;
      BEGIN
         /*******************************/
         /* 1? Nivel -> Pedido Faturado */
         /*******************************/
         FOR nivel_1 IN ( SELECT *
                            FROM wg_fsulmaq_com008
                           WHERE itpdv_id_nvl_1 = pi_itpdv_id
                             AND nivel          = 1 )
         LOOP
            /*********************************/
            /* 2? Nivel -> Pedido Necessario */
            /*********************************/
            FOR nivel_2 IN ( SELECT *
                               FROM wg_fsulmaq_com008
                              WHERE itpdv_id_nvl_1 = nivel_1.itpdv_id_nvl_1
                                AND nivel          = 2
                                AND tipo           = pi_tipo )
            LOOP
               v_existe_alterado := FALSE;
               v_vlr_total       := ROUND(((nivel_1.vlr_total*nivel_2.perc_abs)/100),2);

               UPDATE wg_fsulmaq_com008
                  SET vlr_total     = v_vlr_total
                    , vlr_total_ori = v_vlr_total
--                    , onde = DBMS_UTILITY.format_call_stack
                WHERE itpdv_id_nvl_1 = nivel_2.itpdv_id_nvl_1
                  AND itpdv_id_nvl_2 = nivel_2.itpdv_id_nvl_2
                  AND nivel          = 2
                  AND tipo           = pi_tipo;

               v_soma_vlr_total := 0;
               /********************************/
               /* 3? Nivel -> Pedido Expedic?o */
               /********************************/
               FOR nivel_3 IN ( SELECT *
                                  FROM wg_fsulmaq_com008
                                 WHERE itpdv_id_nvl_1 = nivel_2.itpdv_id_nvl_1
                                   AND itpdv_id_nvl_2 = nivel_2.itpdv_id_nvl_2
                                   AND nivel          = 3
                                   AND tipo           = pi_tipo )
               LOOP
                  --Calcula o Valor dos Itens de 3? Nivel
                  v_vlr_total_ori := ROUND(((nivel_3.perc_abs*v_vlr_total)/100),2); --Valor Original

                  IF nivel_3.alterado = 1 AND pi_considera = 1 THEN
                     v_vlr_total_exp   := ROUND(nivel_3.vlr_total,2);
                     v_existe_alterado := TRUE;
                  ELSE
                     v_vlr_total_exp := ROUND(v_vlr_total_ori,2);
                  END IF;

                  v_soma_vlr_total := v_soma_vlr_total+v_vlr_total_exp;

                  UPDATE wg_fsulmaq_com008
                     SET vlr_total_ori = v_vlr_total_ori
                       , vlr_total     = v_vlr_total_exp
--                       , onde = DBMS_UTILITY.format_call_stack
                   WHERE itpdv_id_nvl_1 = nivel_3.itpdv_id_nvl_1
                     AND itpdv_id_nvl_2 = nivel_3.itpdv_id_nvl_2
                     AND itpdv_id_nvl_3 = nivel_3.itpdv_id_nvl_3
                     --AND alterado       = 0 
                     AND nivel          = 3
                     AND NOT EXISTS(SELECT 1
                                      FROM THIST_MOV_ITE_PDV HIST
                                    WHERE HIST.ITPDV_ID = wg_fsulmaq_com008.Itpdv_id_nvl_3
                                      AND HIST.ITNFS_ID IS NOT NULL)
                     AND tipo           = pi_tipo;
               END LOOP;

               --Recalcula e redistribui os valores conforme o que foi alterado manualmente
               /********************************/
               /* 3? Nivel -> Pedido Expedic?o */
               /********************************/
               IF v_existe_alterado AND pi_considera = 1 THEN
                  BEGIN
                     SELECT ROUND(SUM(vlr_total_ori)-SUM(DECODE(alterado, 1, vlr_total, 0)),2)
                          , ROUND(SUM(DECODE(alterado, 0, NVL(custo_medio, 0), 0)),2)
                       INTO v_soma
                          , v_sum_custo_medio_alt
                       FROM wg_fsulmaq_com008
                      WHERE itpdv_id_nvl_1 = nivel_2.itpdv_id_nvl_1
                        AND itpdv_id_nvl_2 = nivel_2.itpdv_id_nvl_2
                        AND nivel = 3
                        AND tipo           = pi_tipo;
                  EXCEPTION
                     WHEN NO_DATA_FOUND THEN
                        v_soma                := NULL;
                        v_sum_custo_medio_alt := NULL;
                  END;

                  v_soma_vlr_total := 0;
                  FOR nivel_3 IN ( SELECT *
                                     FROM wg_fsulmaq_com008
                                    WHERE itpdv_id_nvl_1 = nivel_2.itpdv_id_nvl_1
                                      AND itpdv_id_nvl_2 = nivel_2.itpdv_id_nvl_2
                                      AND nivel          = 3
                                      AND alterado       = 0
                                      AND tipo           = pi_tipo )
                  LOOP
                     v_new_vlr        := ROUND(((v_soma*(nivel_3.custo_medio*100)/greatest(nvl(v_sum_custo_medio_alt,1),1))/100),2);
                     v_soma_vlr_total := v_soma_vlr_total+v_new_vlr;

                     UPDATE wg_fsulmaq_com008
                        SET vlr_total = v_new_vlr
--                        , onde = DBMS_UTILITY.format_call_stack
                      WHERE itpdv_id_nvl_1 = nivel_3.itpdv_id_nvl_1
                        AND itpdv_id_nvl_2 = nivel_3.itpdv_id_nvl_2
                        AND itpdv_id_nvl_3 = nivel_3.itpdv_id_nvl_3
                       -- AND alterado       = 0 
                        AND nivel          = 3
                        AND NOT EXISTS(SELECT 1
                                         FROM THIST_MOV_ITE_PDV HIST
                                       WHERE HIST.ITPDV_ID = wg_fsulmaq_com008.Itpdv_id_nvl_3
                                         AND HIST.ITNFS_ID IS NOT NULL)
                        AND tipo           = pi_tipo;
                  END LOOP;
               END IF;

               /*########################################*/
               /*# Arredondamento de valores (3? nivel) #*/
               /*########################################*/
               IF v_existe_alterado AND pi_considera = 1 THEN
                  BEGIN
                     SELECT SUM(vlr_total)
                       INTO v_vlr_total_alt
                       FROM wg_fsulmaq_com008
                      WHERE itpdv_id_nvl_1 = nivel_2.itpdv_id_nvl_1
                        AND itpdv_id_nvl_2 = nivel_2.itpdv_id_nvl_2
                        AND nivel          = 3
                        --AND alterado       = 0 
                        AND tipo           = pi_tipo
                        AND alterado       = 1;
                  EXCEPTION
                     WHEN NO_DATA_FOUND THEN
                        v_vlr_total_alt := NULL;
                  END;

                  IF (v_soma_vlr_total+v_vlr_total_alt) <> v_vlr_total THEN
                     ARREDONDA_VALORES (pi_vlr_ori       => (v_soma_vlr_total+v_vlr_total_alt)
                                       ,pi_vlr_des       => v_vlr_total
                                       ,pi_campo         => 'VLR_TOTAL'
                                       ,pi_nivel         => 2
                                       ,pi_tipo          => pi_tipo
                                       ,pi_alterado       => 1
                                       ,pi_itpdv_id_nvl_1=> nivel_1.itpdv_id_nvl_1
                                       ,pi_itpdv_id_nvl_2=> NULL
                                       ,pi_itpdv_id_nvl_3=> NULL
                                       );
                  END IF;
               ELSE
                  IF v_soma_vlr_total <> v_vlr_total THEN
                     ARREDONDA_VALORES (pi_vlr_ori       => v_soma_vlr_total
                                       ,pi_vlr_des       => v_vlr_total
                                       ,pi_campo         => 'VLR_TOTAL'
                                       ,pi_nivel         => 2
                                       ,pi_tipo          => pi_tipo
                                       ,pi_alterado      => 0--NULL -- Sol. 293361
                                       ,pi_itpdv_id_nvl_1=> nivel_1.itpdv_id_nvl_1
                                       ,pi_itpdv_id_nvl_2=> NULL
                                       ,pi_itpdv_id_nvl_3=> NULL
                                       );
                  END IF;
               END IF;
               /*########################################*/
            END LOOP;

            ----------------------------------------------------------------
            ---------------------- Solicita??o 293361 ----------------------
            ----------------------------------------------------------------
            -- Soma todos os Itens de segundo n?vel
            v_aux := 0;
            BEGIN
               SELECT NVL(SUM(vlr_total), 0)
                 INTO v_aux
                 FROM wg_fsulmaq_com008
                WHERE tipo           = pi_tipo
                  AND nivel          = 2
                  AND itpdv_id_nvl_1 = nivel_1.itpdv_id_nvl_1;
            EXCEPTION
               WHEN NO_DATA_FOUND THEN
                  v_aux := 0;
            END;

            IF NVL(v_aux, 0) <> NVL(nivel_1.vlr_total, 0) THEN
               v_dif := ABS(NVL(v_aux, 0)-NVL(nivel_1.vlr_total, 0));

               IF NVL(v_aux, 0) > NVL(nivel_1.vlr_total, 0) THEN
                  v_controle := 0; --Subtrai
               ELSE
                  v_controle := 1; --Soma
               END IF;

               -- Ajusta o valor do ?ltimo Item de segundo n?vel
               UPDATE wg_fsulmaq_com008
                  SET vlr_total = DECODE(v_controle, 0, vlr_total-v_dif, vlr_total+v_dif)
--                  , onde = DBMS_UTILITY.format_call_stack
                WHERE tipo           = pi_tipo
                  AND nivel          = 2
                  AND itpdv_id_nvl_1 = nivel_1.itpdv_id_nvl_1
                  AND ordenacao      = (SELECT MAX(ordenacao)
                                          FROM wg_fsulmaq_com008
                                         WHERE tipo           = pi_tipo
                                           AND nivel          = 2
                                           AND itpdv_id_nvl_1 = nivel_1.itpdv_id_nvl_1);
            END IF;

            -- Soma todos os Itens de terceiro n?vel
            v_aux := 0;
            BEGIN
               SELECT NVL(SUM(vlr_total), 0)
                 INTO v_aux
                 FROM wg_fsulmaq_com008
                WHERE tipo           = pi_tipo
                  AND nivel          = 3
                  AND itpdv_id_nvl_1 = nivel_1.itpdv_id_nvl_1;
            EXCEPTION
               WHEN NO_DATA_FOUND THEN
                  v_aux := 0;
            END;

            IF NVL(v_aux, 0) <> NVL(nivel_1.vlr_total, 0) THEN
               v_dif := ABS(NVL(v_aux, 0)-NVL(nivel_1.vlr_total, 0));

               IF NVL(v_aux, 0) > NVL(nivel_1.vlr_total, 0) THEN
                  v_controle := 0; --Subtrai
               ELSE
                  v_controle := 1; --Soma
               END IF;

               -- Ajusta o valor do ?ltimo Item de segundo n?vel
               UPDATE wg_fsulmaq_com008
                  SET vlr_total = DECODE(v_controle, 0, vlr_total-v_dif, vlr_total+v_dif)
--                  , onde = DBMS_UTILITY.format_call_stack
                WHERE tipo           = pi_tipo
                  AND nivel          = 3
                  AND alterado       = 0 
                  AND NOT EXISTS(SELECT 1
                                   FROM THIST_MOV_ITE_PDV HIST
                                 WHERE HIST.ITPDV_ID = wg_fsulmaq_com008.Itpdv_id_nvl_3
                                   AND HIST.ITNFS_ID IS NOT NULL)
                  AND itpdv_id_nvl_1 = nivel_1.itpdv_id_nvl_1
                  AND ordenacao      = (SELECT MAX(ordenacao)
                                          FROM wg_fsulmaq_com008
                                         WHERE tipo           = pi_tipo
                                           AND nivel          = 3
                                           AND alterado       = 0 
                                           AND itpdv_id_nvl_1 = nivel_1.itpdv_id_nvl_1);
            END IF;
            ----------------------------------------------------------------
            -------------------- Fim Solicita??o 293361 --------------------
            ----------------------------------------------------------------
         END LOOP;
      END CALCULA_VALORES;
   BEGIN
      --Valida se existem itens sem custo
      BEGIN
         SELECT COUNT(*)
           INTO v_count
           FROM wg_fsulmaq_com008
          WHERE itpdv_id_nvl_1      = pi_itpdv_id
            AND tipo                = pi_tipo
            AND ALTERADO            = 0
            AND nivel               = 3
            AND NVL(custo_medio, 0) <= 0;
      EXCEPTION
         WHEN NO_DATA_FOUND THEN
            v_count := 0;
      END;
      
      IF NVL(v_count, 0) > 0 THEN
         --Se algum item n?o possuir custo medio ent?o atualiza toda a estrutura para NULL
         UPDATE wg_fsulmaq_com008
            SET vlr_total = NULL
--            , onde = DBMS_UTILITY.format_call_stack
          WHERE itpdv_id_nvl_1 = pi_itpdv_id
            AND tipo           = pi_tipo
            AND ALTERADO       = 0
            AND nivel          IN (2,3);

         UPDATE wg_fsulmaq_com008
            SET custo_medio = NULL
--             , onde = DBMS_UTILITY.format_call_stack
          WHERE itpdv_id_nvl_1      = pi_itpdv_id
            AND tipo                = pi_tipo
            AND ALTERADO            = 0
            AND nivel               = 3
            AND NVL(custo_medio, 0) <= 0;
      ELSE
         --IF pi_considera = 1 THEN
         --comentado em visita dia 15/02/2016 cristiano Diniz
         /*IF pi_considera = 1 AND pi_tipo <> 'CONSULTA' THEN --Sol. 293361: N?o deve validar os valores na Consulta do Agrupamento (FSULMAQ_COM008)
            VALIDA_VALORES(v_erro);
         END IF;
         */
         IF v_erro IS NULL THEN
            CALCULA_CUSTOS;
            CALCULA_VALORES;
         ELSE
            po_erro := v_erro;
         END IF;
      END IF;
   END RECALCULA_VALORES_TELA;
   
   PROCEDURE GRAVA_VALORES_VINCULOS ( pi_itpdv_id  IN wg_fsulmaq_com008.itpdv_id_nvl_1%TYPE
                                    , pi_tipo      IN VARCHAR2 ) IS
      v_alterado NUMBER(1);
      v_existe   NUMBER(1);
      v_vlr_liq  NUMBER(17,8);
   BEGIN
    
      FOR c_itens IN ( SELECT nivel
                            , vlr_total_ori
                            , vlr_total
                            , setor_seq
                            , num_opp
                            , itpdv_id_nvl_1
                            , itpdv_id_nvl_2
                            , itpdv_id_nvl_3
                            , calc_automatico
                            , alterado
                         FROM wg_fsulmaq_com008
                        WHERE nivel > 1
                          AND EXISTS (SELECT 1
                                        FROM tsulmaq_vinc_pdv
                                       WHERE itpdv_id = wg_fsulmaq_com008.itpdv_id_nvl_1)
                          AND itpdv_id_nvl_1 = pi_itpdv_id
                          AND tipo           = pi_tipo )
      LOOP
         IF c_itens.nivel = 2 THEN
            BEGIN
               SELECT 1
                 INTO v_existe
                 FROM thist_mov_ite_pdv hist
                WHERE hist.itpdv_id = c_itens.itpdv_id_nvl_2
                  AND hist.itnfs_id IS NOT NULL
                  AND ROWNUM = 1;
            EXCEPTION 
               WHEN NO_DATA_FOUND THEN 
                  v_existe := 0;       
            END;   

            IF v_existe = 0 THEN 
               UPDATE tsulmaq_vinc_pdv
                  SET valor = NVL(c_itens.vlr_total,0)
                WHERE setor_seq = c_itens.setor_seq
                  AND num_opp   = c_itens.num_opp
                  AND itpdv_id  = c_itens.itpdv_id_nvl_1;

               --Atualiza o valor do item no pedido
               UPDATE titens_pdv
                  SET vlr_liq = ROUND((c_itens.vlr_total/ greatest(nvl(qtde,1),1) )-(((c_itens.vlr_total/greatest(nvl(qtde,1),1))*aliq_ipi)/100),2)
                    , vlr_liq_alterado = 1
                WHERE id = c_itens.itpdv_id_nvl_2
               RETURNING vlr_liq 
                    INTO v_vlr_liq;

            END IF;
         ELSIF c_itens.nivel = 3 THEN
            IF nvl(c_itens.vlr_total,0) <> nvl(c_itens.vlr_total_ori,0) AND nvl(c_itens.alterado,0) = 1 THEN
               v_alterado := 1;
            ELSE
               v_alterado := 0;
            END IF;
 
            BEGIN
               SELECT 1
                 INTO v_existe
                 FROM thist_mov_ite_pdv hist
               WHERE hist.itpdv_id = c_itens.itpdv_id_nvl_3
                 AND hist.itnfs_id IS NOT NULL
                 AND ROWNUM = 1;  
            EXCEPTION 
              WHEN NO_DATA_FOUND THEN 
                v_existe := 0;       
            END;   
            
            IF v_existe = 0 THEN 
               UPDATE sdi_listas_fabricacao
                  SET vlr_total = c_itens.vlr_total
                    , alterado  = v_alterado
                WHERE setor_seq    = c_itens.setor_seq
                  AND oportunidade = c_itens.num_opp
                  AND itpdv_id     = c_itens.itpdv_id_nvl_3;
                  
               --Atualiza o valor do item no pedido
               UPDATE titens_pdv
                  SET vlr_liq = ROUND((c_itens.vlr_total/greatest(nvl(qtde,1),1))-(((c_itens.vlr_total/greatest(nvl(qtde,1),1))*aliq_ipi)/100),2)
                    , vlr_liq_alterado = 1
--                    , PROJETO_EXP = c_itens.vlr_total --ADD PARA FINS DE LOG REMOVER DEPOIS 
                WHERE id = c_itens.itpdv_id_nvl_3
               RETURNING vlr_liq 
                    INTO v_vlr_liq;
            
            END IF;
         END IF;
      END LOOP;
          
   END;
   
   
   PROCEDURE GRAVA_VALORES_CANETACO ( pi_itpdv_id  IN wg_fsulmaq_com008.itpdv_id_nvl_1%TYPE
                                    , pi_tipo      IN VARCHAR2 ) 
   IS
      v_alterado NUMBER(1);
      v_existe   NUMBER(1);
     -- v_vlr_liq  NUMBER(17,8);
   BEGIN
      FOR c_itens IN ( SELECT nivel
                            , vlr_total_ori
                            , vlr_total
                            , setor_seq
                            , num_opp
                            , itpdv_id_nvl_1
                            , itpdv_id_nvl_2
                            , itpdv_id_nvl_3
                            , calc_automatico
                            , alterado
                         FROM wg_fsulmaq_com008
                        WHERE nivel = 3
                         -- AND alterado = 1 
                          AND itpdv_id_nvl_1 = pi_itpdv_id
                          AND tipo           = pi_tipo )
      LOOP
         
         BEGIN
            SELECT 1
              INTO v_existe
              FROM thist_mov_ite_pdv hist
            WHERE hist.itpdv_id = c_itens.itpdv_id_nvl_3
              AND hist.itnfs_id IS NOT NULL
              AND ROWNUM = 1;  
         EXCEPTION 
           WHEN NO_DATA_FOUND THEN 
             v_existe := 0;       
         END;   
         
         IF v_existe = 0 THEN 
        
         
            IF c_itens.alterado = 1 THEN 
               UPDATE sdi_listas_fabricacao
                  SET vlr_total = c_itens.vlr_total
                    , alterado  = c_itens.alterado
                WHERE setor_seq    = c_itens.setor_seq
                  AND oportunidade = c_itens.num_opp
                  AND itpdv_id     = c_itens.itpdv_id_nvl_3;
            
               --Atualiza o valor do item no pedido
               UPDATE titens_pdv
                  SET vlr_liq = ROUND((NVL(c_itens.vlr_total,0)/greatest(nvl(qtde,1),1))-(((NVL(c_itens.vlr_total,0)/greatest(nvl(qtde,1),1))*NVL(aliq_ipi,0))/100),2)
                    , vlr_liq_alterado = c_itens.alterado
                WHERE id = c_itens.itpdv_id_nvl_3;
         
            ELSE
               UPDATE sdi_listas_fabricacao
                  SET alterado  = c_itens.alterado
                WHERE setor_seq    = c_itens.setor_seq
                  AND oportunidade = c_itens.num_opp
                  AND itpdv_id     = c_itens.itpdv_id_nvl_3;
            
               --Atualiza o valor do item no pedido
               UPDATE titens_pdv
                  SET vlr_liq_alterado = c_itens.alterado
                WHERE id = c_itens.itpdv_id_nvl_3;
            END IF;
         END IF; 
        
      END LOOP;
       COMMIT;   
   END;

   PROCEDURE RECALCULA_PEDIDOS ( pi_itpdv_id  IN wg_fsulmaq_com008.itpdv_id_nvl_1%TYPE
                               , pi_tipo      IN VARCHAR2 ) IS
      v_alterado NUMBER(1);
   BEGIN
      --Recalcula os pedidos de 2? e 3? niveis
      FOR c_recalc IN ( SELECT DISTINCT itpdv.pdv_id
                          FROM wg_fsulmaq_com008 wg
                             , titens_pdv        itpdv
                         WHERE wg.itpdv_id_nvl_2 = itpdv.id
                           AND wg.nivel = 2
                           AND EXISTS (SELECT 1
                                         FROM tsulmaq_vinc_pdv
                                        WHERE itpdv_id = wg.itpdv_id_nvl_1)
                           AND wg.itpdv_id_nvl_1 = pi_itpdv_id
                           AND wg.tipo           = pi_tipo
                         UNION
                        SELECT DISTINCT itpdv.pdv_id
                          FROM wg_fsulmaq_com008 wg
                             , titens_pdv        itpdv
                         WHERE wg.itpdv_id_nvl_3 = itpdv.id
                           AND wg.nivel = 3
                           AND EXISTS (SELECT 1
                                         FROM tsulmaq_vinc_pdv
                                        WHERE itpdv_id = wg.itpdv_id_nvl_1)
                           AND wg.itpdv_id_nvl_1 = pi_itpdv_id
                           AND wg.tipo           = pi_tipo )
      LOOP
         COM_PDV_RECALCULA_PEDIDO(c_recalc.pdv_id);
      END LOOP;
   END;

   /*****************************************************************************************/
   /****************** PROJETO 157386 - Agrupamento de Itens (Faturamento) ******************/
   /*****************************************************************************************/

   PROCEDURE IDE_VALIDA_INF_ETQ IS
      /***************************************************************************************
      Procedure que valida se foram informados os dados especificos no programa FUTL0261,
      bot?o "Adicionais". Essa validac?o ocorre quando o programa selecionado for o FREC0200
      (Processo 6).
      ***************************************************************************************/
      pi_empr_id   tempresas.id%TYPE;
      pi_programa  VARCHAR2(4000);
      pio_processo NUMBER(2);
      
      v_existe     NUMBER(1);
      v_erro       VARCHAR2(4000);
   BEGIN
      FOCCO3I_PARAMETROS.GET_PARAMETRO('pi_empr_id'  , pi_empr_id);
      FOCCO3I_PARAMETROS.GET_PARAMETRO('pi_programa' , pi_programa);
      FOCCO3I_PARAMETROS.GET_PARAMETRO('pio_processo', pio_processo);

      IF pio_processo = 6 THEN
         BEGIN
            SELECT 1
              INTO v_existe
              FROM wg_fsulmaq_com012
             WHERE ROWNUM = 1;
         EXCEPTION
            WHEN NO_DATA_FOUND THEN
               v_existe := 0;
         END;
         
         IF v_existe = 0 THEN
            v_erro := 'Cadastre as informa??es adicionais para prosseguir. Utilize o bot?o "Adicionais"!';
         END IF;
      END IF;

      FOCCO3I_PARAMETROS.SET_PARAMETRO('pio_processo', pio_processo);
      IF v_erro IS NOT NULL THEN
         FOCCO3I_PARAMETROS.SET_PARAMETRO('po_erro'  , v_erro);
         FOCCO3I_PARAMETROS.SET_PARAMETRO('po_tp_msg', 'E');
         FOCCO3I_PARAMETROS.SET_PARAMETRO('po_raise' , TRUE);
      END IF;
   END IDE_VALIDA_INF_ETQ;
   
   PROCEDURE IDE_GERA_WG_ETIQ_NFE IS
      /********************************************************************************
      Procedure que gera dados especificos na tabela wg_sulmaq_futl0261, conforme
      os dados previamente gerados na wg_sel_etiq.
      Esse processo e executado pelos seguintes programas:
      #Processo 2:
      ->FUTL0261: selecionando o programa FEST0112 (modos "Impress?o" e "Reimpress?o");
      ->FPRD0201: no apontamento da ultima operac?o (tela de apontamentos, bot?o OK);
      #Processo 6:
      ->FUTL0261: selecionando o programa FREC0200 (modo "Impress?o");
      ********************************************************************************/
      
      pi_ind_processo      NUMBER;
      pi_processos         VARCHAR2(4000);
      pi_itens             VARCHAR2(4000);
      pi_configurado       NUMBER;
      pi_lotes             VARCHAR2(4000);
      pi_referencias       VARCHAR2(4000);
      pi_qtde              NUMBER;
      pi_modelo            VARCHAR2(4000);
      pi_empr              NUMBER;
      pi_tprog_etiqueta_id NUMBER;
      
      v_num_opp            NUMBER(30);
      v_setor_seq          VARCHAR2(40);
      v_cod_cli            tclientes.cod_cli%TYPE;
      v_desc_cli           tclientes.descricao%TYPE;
      v_cidade             tcidades.cidade%TYPE;
      v_uf                 tufs.uf%TYPE;
      v_tmasc_item_id      tmasc_item.id%TYPE;
      
      v_erro               VARCHAR2(4000);
      erro_processo        EXCEPTION;
      
   BEGIN
      FOCCO3I_PARAMETROS.GET_PARAMETRO('pi_ind_processo', pi_ind_processo);
      FOCCO3I_PARAMETROS.GET_PARAMETRO('pi_processos'   , pi_processos);
      FOCCO3I_PARAMETROS.GET_PARAMETRO('pi_qtde'        , pi_qtde);
      FOCCO3I_PARAMETROS.GET_PARAMETRO('pi_modelo'      , pi_modelo);     
      FOCCO3I_PARAMETROS.GET_PARAMETRO('pi_itens'       , pi_itens);      
      FOCCO3I_PARAMETROS.GET_PARAMETRO('pi_configurado' , pi_configurado);
      FOCCO3I_PARAMETROS.GET_PARAMETRO('pi_lotes'       , pi_lotes);
      FOCCO3I_PARAMETROS.GET_PARAMETRO('pi_referencias' , pi_referencias);

      DELETE wg_sulmaq_futl0261;

      IF pi_ind_processo IN (2,6) THEN
         --Se o processo for = 6 (Etiqueta de Produto Comprado) ent?o busca as 
         --informa??es cadastradas nos "Adicionais" do FUTL0261
         IF pi_ind_processo = 6 THEN
            BEGIN
               SELECT num_opp
                    , setor_seq
                 INTO v_num_opp
                    , v_setor_seq
                 FROM wg_fsulmaq_com012
                WHERE ROWNUM = 1;
            EXCEPTION
               WHEN NO_DATA_FOUND THEN
                  v_num_opp   := NULL;
                  v_setor_seq := NULL;
            END;
         END IF;
         
         FOR c_wg IN ( SELECT *
                         FROM wg_sel_etiq )
         LOOP
            --Se o processo for = 2 (Etiqueta de Produto Fabricado) ent?o busca as
            --informa??es na mascara do item
            IF pi_ind_processo = 2 THEN
               --N?o deve utilizar o ID da mascara do cursor (c_wg.tmasc_item_id), pois se o modo escolhido em tela for "Reimpress?o",
               --neste campo a informa??o gravada sera o codigo de barras da tleituras_etiq (campo "Etiqueta" no FUTL0261)
               BEGIN
                  SELECT tmasc_item_id
                    INTO v_tmasc_item_id
                    FROM tordens
                   WHERE id = c_wg.ordem_id;
               EXCEPTION
                  WHEN NO_DATA_FOUND THEN
                     v_tmasc_item_id := NULL;
               END;
            
               -- ADICIONARO REPALCE '-GARANTIA' PARA '' DEVIDO A CHAMADO 277178 CRISTIANO DINIZ
               v_num_opp   := REPLACE(SUBSTR(SULMAQ_AGRUPA_ITENS.RETORNA_MNEMONICO(c_wg.itempr_id, v_tmasc_item_id, 'OPORTUNIDADE'),1,30),'-GARANTIA','');
               --v_setor_seq := SUBSTR(SULMAQ_AGRUPA_ITENS.RETORNA_MNEMONICO(c_wg.itempr_id, v_tmasc_item_id, 'SETOR_SEQ'),1,40);
               
               BEGIN
                  --Utilizada mesma query do programa FSULMAQ_COM008 (bloco de agrupamentos - 3? nivel).
                  SELECT DISTINCT fab.setor_seq
                    INTO v_setor_seq
                    FROM sdi_pdv_expedicao     exp
                       , tpedidos_venda        pdv
                       , titens_pdv            itpdv
                       , sdi_listas_fabricacao fab
                       , titens_comercial      itcm
                       , titens_empr           itempr
                   WHERE exp.pdv_id     = pdv.id
                     AND pdv.id         = itpdv.pdv_id
                     AND itpdv.id       = fab.itpdv_id
                     AND itpdv.itcm_id  = itcm.id
                     AND itcm.itempr_id = itempr.id
                     AND itpdv.qtde_canc < itpdv.qtde
                     AND pdv.tipo       = 'PDV'
                     AND exp.num_opp    = v_num_opp
                     AND itempr.id      = c_wg.itempr_id
                     AND NVL(itpdv.tmasc_item_id,0) = NVL(v_tmasc_item_id,0);
               EXCEPTION
                  WHEN NO_DATA_FOUND THEN
                     v_setor_seq := NULL;
                  WHEN TOO_MANY_ROWS THEN --Sol. 294351
                     /*BR_UTL_ERROS.RAISE_ERRO('N?o foi possivel gerar etiqueta pois existe mais de um Setor / Sequencia nesta Oportunidade.'
                                           ||' Deve ser gerada uma etiqueta manual.', 'I', FALSE);*/

                     v_erro := 'Não foi possível gerar etiqueta pois existe mais de um Setor / Sequencia nesta Oportunidade.'
                                           ||' Deve ser gerada uma etiqueta manual.';
                     RAISE erro_processo;
               END;
               
            ELSIF pi_ind_processo = 6 THEN
               v_tmasc_item_id := c_wg.tmasc_item_id;
            END IF;

            --A partir do pedido faturado s?o buscadas as informa??es de Cliente/Cidade/UF
            BEGIN
                   
             SELECT cli.cod_cli
                    , cli.descricao
                    , cid.cidade
                    , uf.uf
                 INTO v_cod_cli
                    , v_desc_cli
                    , v_cidade
                    , v_uf
                 FROM sdi_pdv_fut           opp
                    , tpedidos_venda        pdv
                    , tclientes             cli
                    , testabelecimentos     est
                    , tcidades              cid
                    , tufs                  uf
                WHERE opp.pdv_id       = pdv.id
                  AND pdv.cli_id       = cli.id
                  AND pdv.est_id_entr  = est.id
                  AND est.cid_id       = cid.id
                  AND cid.uf_id        = uf.id
                  AND opp.num_opp      = v_num_opp;
            EXCEPTION
               WHEN NO_DATA_FOUND THEN
                  v_cod_cli  := NULL;
                  v_desc_cli := NULL;
                  v_cidade   := NULL;
                  v_uf       := NULL;
            END;

            INSERT INTO wg_sulmaq_futl0261
                      ( itempr_id
                      , tmasc_item_id
                      , lote
                      , num_opp
                      , setor_seq
                      , cod_cli
                      , desc_cli
                      , cidade
                      , uf
                      )
               VALUES ( c_wg.itempr_id
                      , v_tmasc_item_id
                      , c_wg.lote
                      , v_num_opp
                      , v_setor_seq
                      , v_cod_cli
                      , v_desc_cli
                      , v_cidade
                      , v_uf
                      );
            
            --TESTE
            UPDATE wg_sel_etiq
               SET ind_tleitura = 1;
            --FIM TESTE
                      
         END LOOP;
      END IF;
   EXCEPTION
      WHEN erro_processo THEN
         FOCCO3I_PARAMETROS.SET_PARAMETRO('po_erro', v_erro);
         RETURN;
   END IDE_GERA_WG_ETIQ_NFE;
   
   PROCEDURE IDE_ALTERA_WG_ETIQUETAS IS
      /********************************************************************************
      Procedure que busca os dados temporarios (especificos) e atualiza essas
      informa??es nos campos 'texto_livre_' da wg_etiquetas.
      Esse processo e executado apos a inser??o dos dados na wg_etiquetas, no programa
      F3I_SEL_ETIQUETA (bot?o Ok).
      ********************************************************************************/
      v_num_opp       NUMBER(30);
      v_setor_seq     VARCHAR2(40);
      v_cod_cli       tclientes.cod_cli%TYPE;
      v_desc_cli      tclientes.descricao%TYPE;
      v_cidade        tcidades.cidade%TYPE;
      v_uf            tufs.uf%TYPE;
      v_itempr_id     titens_empr.id%TYPE;
      v_tmasc_item_id tmasc_item.id%TYPE;
   BEGIN
      FOR c_wg IN ( SELECT *
                      FROM wg_etiquetas
                     ORDER BY registro )
      LOOP
         BEGIN
            SELECT tmasc_item_id
              INTO v_tmasc_item_id
              FROM tordens
             WHERE empr_id   = c_wg.empr_id
               AND num_ordem = c_wg.num_ordem;
         EXCEPTION
            WHEN NO_DATA_FOUND THEN
               v_tmasc_item_id := NULL;
         END;

         BEGIN
            SELECT DISTINCT wg.num_opp
                 , wg.setor_seq
                 , wg.cod_cli
                 , wg.desc_cli
                 , wg.cidade
                 , wg.uf
              INTO v_num_opp
                 , v_setor_seq
                 , v_cod_cli
                 , v_desc_cli
                 , v_cidade
                 , v_uf
              FROM wg_sulmaq_futl0261 wg
                 , titens_empr        itempr
                 , titens             it
             WHERE wg.itempr_id     = itempr.id
               AND itempr.item_id   = it.id
               AND itempr.empr_id   = c_wg.empr_id
               AND it.cod_item      = c_wg.cod_item
               AND NVL(wg.tmasc_item_id, 0) = NVL(v_tmasc_item_id, 0)
               AND NVL(wg.lote, 0)          = NVL(c_wg.num_lote, 0);
         EXCEPTION
            WHEN NO_DATA_FOUND THEN
               v_num_opp   := NULL;
               v_setor_seq := NULL;
               v_cod_cli   := NULL;
               v_desc_cli  := NULL;
               v_cidade    := NULL;
               v_uf        := NULL;
         END;

         UPDATE wg_etiquetas
            SET texto_livre1 = TO_CHAR(v_num_opp)
              , texto_livre2 = v_setor_seq
              , texto_livre3 = v_cod_cli
              , texto_livre4 = v_desc_cli
              , texto_livre5 = v_cidade
              , texto_livre6 = v_uf
          WHERE registro = c_wg.registro;
      END LOOP;
      
   END;
   
   PROCEDURE INSERE_WG_SEL_ETIQ ( pi_ind_processo IN NUMBER 
                                , pi_processos    IN VARCHAR2
                                , pi_qtde         IN NUMBER
                                , pi_modelo       IN VARCHAR2
                                , pi_empr         IN NUMBER
                                , po_erro        OUT VARCHAR2
                                ) IS

     /********************************************************************************
     Procedure que possui o mesmo objetivo da F3I_GERA_WG_ETIQ (gerar a wg_sel_etiq)
     (Processo 2), porem a quantidade utilizada nos calculos e a quantidade passada
     no parametro pi_qtde e n?o a buscada no cursor.
     Esse processo e utilizado no programa FPRD0201, quando for realizado o apontamento
     da ultima opera??o (Tela de Apontamentos, bot?o "Ok").
     ********************************************************************************/
      curs_sql            INTEGER;
      status              VARCHAR2(80);
      v_ind_gera_etiq     NUMBER(10);
      v_epp_ids           VARCHAR2(200);
      p_query             VARCHAR2(10000) := NULL;
      p_where             VARCHAR2(4000)  := NULL;
      p_from              VARCHAR2(4000)  := NULL;
      v_itempr_id         NUMBER(10);
      v_tmasc_item_id     NUMBER(10);
      v_qtde              NUMBER(19,8);
      v_itens_volume      NUMBER(19,8);
      v_unid_med          VARCHAR2(3);
      v_lote              VARCHAR2(20);
      v_ordem_id          NUMBER(10);
      v_lote_id           NUMBER(10);
      v_cod_barra         NUMBER(20);
      v_seq               NUMBER(10) := 0;
   BEGIN
      v_ind_gera_etiq := 1;

      BEGIN
         SELECT WM_CONCAT(ID)
           INTO v_epp_ids
           FROM ttp_mov_estq
          WHERE uso_est = 'EPP';
      EXCEPTION
         WHEN OTHERS THEN
            v_epp_ids := NULL;
      END;

      p_query := 'SELECT tc.itempr_id
                       , tor.tmasc_item_id
                       , NVL(SUM(DECODE(tm.ENT_SAI,''E'',tm.qtde,tm.qtde*-1)),0) qtde 
                       , tc.itens_volume
                       , tu.cod_unid_med
                       , tl.cod_lote
                       , tor.id
                       , tl.id
                       , null cod_barra ';
      
      p_from  := 'FROM tordens tor
                     , titens_comercial tc
                     , titens_planejamento tp
                     , titens_estoque ts
                     , tunid_med tu
                     , tmov_estq tm
                     , titens_lote til
                     , tlotes tl ';
      
      p_where := 'WHERE tor.itpl_id  = tp.id ';
      p_where := p_where||'  AND tp.itempr_id = tc.itempr_id';
      p_where := p_where||'  AND tu.id        = ts.unid_med_id';
      p_where := p_where||'  AND tc.itempr_id = ts.itempr_id';
      p_where := p_where||'  AND tm.ite_lote_id = til.id(+)';
      p_where := p_where||'  AND til.lot_id     = tl.id(+)';
      p_where := p_where||'  AND tm.tmves_id IN ('||v_epp_ids||')';
      p_where := p_where||'  AND tor.id       = tm.ordem_id';

      IF pi_processos IS NOT NULL THEN
         p_where := p_where || ' AND '||FOCCO3I_UTIL.intervalo('tor.id',TO_NUMBER(pi_processos),'N');
      END IF;

      p_where := p_where|| ' GROUP BY tc.itempr_id
                                    , tor.tmasc_item_id
                                    , tm.ENT_SAI
                                    , tc.itens_volume
                                    , tu.cod_unid_med
                                    , tl.cod_lote
                                    , tor.ID
                                    , tl.ID';

      
      p_query := p_query || p_from || p_where;

      curs_sql := DBMS_SQL.OPEN_CURSOR;
      
      DBMS_SQL.PARSE(curs_sql, p_query, 0);
      DBMS_SQL.DEFINE_COLUMN(curs_sql, 1, v_itempr_id);
      DBMS_SQL.DEFINE_COLUMN(curs_sql, 2, v_tmasc_item_id);
      DBMS_SQL.DEFINE_COLUMN(curs_sql, 3, v_qtde);
      DBMS_SQL.DEFINE_COLUMN(curs_sql, 4, v_itens_volume);
      DBMS_SQL.DEFINE_COLUMN(curs_sql, 5, v_unid_med,3);
      DBMS_SQL.DEFINE_COLUMN(curs_sql, 6, v_lote,20);
      DBMS_SQL.DEFINE_COLUMN(curs_sql, 7, v_ordem_id);
      DBMS_SQL.DEFINE_COLUMN(curs_sql, 8, v_lote_id);
      DBMS_SQL.DEFINE_COLUMN(curs_sql, 9, v_cod_barra);
      
      status := DBMS_SQL.EXECUTE(curs_sql);
      
      WHILE (DBMS_SQL.FETCH_ROWS(curs_sql) > 0) LOOP
         DBMS_SQL.COLUMN_VALUE(curs_sql, 1, v_itempr_id);
         DBMS_SQL.COLUMN_VALUE(curs_sql, 2, v_tmasc_item_id);
         DBMS_SQL.COLUMN_VALUE(curs_sql, 3, v_qtde);
         DBMS_SQL.COLUMN_VALUE(curs_sql, 4, v_itens_volume);
         DBMS_SQL.COLUMN_VALUE(curs_sql, 5, v_unid_med);
         DBMS_SQL.COLUMN_VALUE(curs_sql, 6, v_lote);
         DBMS_SQL.COLUMN_VALUE(curs_sql, 7, v_ordem_id);
         DBMS_SQL.COLUMN_VALUE(curs_sql, 8, v_lote_id);
         DBMS_SQL.COLUMN_VALUE(curs_sql, 9, v_cod_barra);

         IF NVL(v_itens_volume,0) = 0 THEN
            --v_itens_volume := v_qtde;
            v_itens_volume := pi_qtde;
         END IF;

         IF NVL(v_qtde,0) <> 0 THEN
            BEGIN
               v_seq := v_seq + 1;

               INSERT INTO wg_sel_etiq ( itempr_id
                                       , tmasc_item_id
                                       , qtde_itens
                                       , modelo
                                       , qtde_it_vol
                                       , lote
                                       , ordem_id
                                       , lote_id
                                       , cod_barra
                                       , ind_tleitura
                                       , unid_med 
                                       , seq
                                       )                                                                                                                      -- Sol 121409
                                VALUES ( v_itempr_id
                                       , v_tmasc_item_id
                                       , NVL(pi_qtde, NVL(v_qtde, 0)) -- Alterado para usar a quantidade do parametro pi_qtde
                                       , pi_modelo
                                       , v_itens_volume
                                       , NVL ( v_lote, 0 )
                                       , v_ordem_id
                                       , v_lote_id
                                       , v_cod_barra
                                       , v_ind_gera_etiq
                                       , v_unid_med 
                                       , v_seq
                                       );
            EXCEPTION
               WHEN OTHERS THEN
                  NULL;
            END;

            DECLARE
             v_unid_med_id tunid_med.ID%TYPE;
            BEGIN
               BEGIN
                 SELECT u.id
                   INTO v_unid_med_id
                   FROM tunid_med u
                  WHERE u.cod_unid_med = v_unid_med;
               EXCEPTION
                  WHEN NO_DATA_FOUND THEN
                     v_unid_med_id := NULL;
               END;

               INSERT INTO wg_qtd_etiq ( itempr_id
                                       , tmasc_item_id
                                       , lote
                                       , qtde_etiq
                                       , qtde_it_etiq
                                       , unid_med_id 
                                       )
                                VALUES ( v_itempr_id
                                       , v_tmasc_item_id
                                       , NVL(v_lote,0)
                                       , TRUNC(NVL(pi_qtde,0)/NVL(v_itens_volume,1),0)--TRUNC(NVL(v_qtde,0)/NVL(v_itens_volume,1),0)
                                       , NVL(v_itens_volume,1)
                                       , v_unid_med_id
                                       );
            EXCEPTION
               WHEN OTHERS THEN
                  NULL;
            END;
         END IF;
      END LOOP;
      DBMS_SQL.CLOSE_CURSOR(curs_sql);
      
      FOCCO3I_PARAMETROS.SET_PARAMETRO('pi_ind_processo', pi_ind_processo);
      FOCCO3I_PARAMETROS.SET_PARAMETRO('pi_processos'   , pi_processos);
      FOCCO3I_PARAMETROS.SET_PARAMETRO('pi_qtde'        , pi_qtde);
      FOCCO3I_PARAMETROS.SET_PARAMETRO('pi_modelo'      , pi_modelo);
      FOCCO3I_PARAMETROS.SET_PARAMETRO('pi_itens'       , '');
      FOCCO3I_PARAMETROS.SET_PARAMETRO('pi_configurado' , '');
      FOCCO3I_PARAMETROS.SET_PARAMETRO('pi_lotes'       , '');
      FOCCO3I_PARAMETROS.SET_PARAMETRO('pi_referencias' , '');
      
      SULMAQ_AGRUPA_ITENS.IDE_GERA_WG_ETIQ_NFE;
      FOCCO3I_PARAMETROS.GET_PARAMETRO('po_erro'        , po_erro);

   END INSERE_WG_SEL_ETIQ;

   /***********************************
   ***Projeto 157386 Cristiano Diniz***
   ***     FATURAMENTO FFAT0220     ***
   ************************************/

   PROCEDURE IDE_DESCONSIDERA_RESERVA
   IS
     /*******************************************
     IDE criada para desconsiderar a quantidade
     reservada
     ********************************************/
     
     v_empr_id   tempresas.id%TYPE;
     v_itplc_id  titens_plc.id%TYPE;
     v_qtde      titens_plc.qtde%TYPE;

   BEGIN
       FOCCO3I_PARAMETROS.GET_PARAMETRO('pi_empr_id'  , v_empr_id);
       FOCCO3I_PARAMETROS.GET_PARAMETRO('pi_itplc_id' , v_itplc_id); 
       FOCCO3I_PARAMETROS.GET_PARAMETRO('pio_qtde'    , v_qtde);
       
       BEGIN 
          SELECT qtde
            INTO v_qtde 
            FROM titens_plc
          WHERE id = v_itplc_id;
       EXCEPTION
         WHEN NO_DATA_FOUND THEN   
           NULL;
       END;  
       
       FOCCO3I_PARAMETROS.SET_PARAMETRO('pio_qtde'    , v_qtde);
       
   END;

   PROCEDURE IDE_ALTERA_QUERY_MOVESTQ
   IS 
      v_sessao        NUMBER(10);
      v_itempr_id     NUMBER(10);
      v_wgitnfs_id    NUMBER(10);
      v_empr_id       NUMBER(10);
      v_select        VARCHAR2(4000);
      v_select_2        VARCHAR2(4000);
   
   BEGIN
       FOCCO3I_PARAMETROS.GET_PARAMETRO('pi_sessao'    , V_sessao    );
       FOCCO3I_PARAMETROS.GET_PARAMETRO('pi_itempr_id' , V_itempr_id );
       FOCCO3I_PARAMETROS.GET_PARAMETRO('pi_num_linha' , V_wgitnfs_id);
       FOCCO3I_PARAMETROS.GET_PARAMETRO('pi_empr_id'   , V_empr_id   ); 
       FOCCO3I_PARAMETROS.GET_PARAMETRO('pi_cursor',     v_select     ); 
       
       
       v_select_2 := REPLACE(v_select,'SELECT sessao','SELECT DISTINCT sessao');
       
       
       FOCCO3I_PARAMETROS.SET_PARAMETRO('po_cursor',    v_select_2     ); 
   
   END;
   /***********************************
   ***Projeto 157386 Cristiano Diniz***
   ***  CONFERENCIA FSULMAQ_COM010  ***
   ************************************/

   FUNCTION RETORNA_IND_ITFAT_TOTAL(PI_ITPDV_ID IN TITENS_PDV.ID%TYPE)
   RETURN NUMBER
   IS
      /*
      ESTA ROTINA UTILIZA A WG_TITENS_NFS, GERADA DURANTE O FATURAMENTO DA NOTA,
      SENDO ASSIM ESTA ROTINA NAO FUNCIONA EM OUTRO LUGAR ALEM DO PROCESSO 
      DO FATURAMENTO DA NOTA 
      
      o itpdv_id e no item faturado ou seja 1? nivel 
      */
      
      v_opp       tsulmaq_vinc_pdv.num_opp%TYPE;
      v_setor_seq tsulmaq_vinc_pdv.setor_seq%TYPE; 
      v_itpdv_id  titens_pdv.id%TYPE :=  NULL;
      v_empr_id   tempresas.id%TYPE;
      
      v_faturado NUMBER(1) := 1;
   BEGIN
      -- BUSCA OPORTUNIDADE E SEQUENCIA DA MASCARA DO ITEM DO PEDIDO FATURADO 
      BEGIN
        
         SELECT SULMAQ_AGRUPA_ITENS.RETORNA_MNEMONICO ( itcm.itempr_id
                                                      , itpdv.tmasc_item_id
                                                      , 'OPORTUNIDADE' )  opp
              , SULMAQ_AGRUPA_ITENS.RETORNA_MNEMONICO ( itcm.itempr_id
                                                      , itpdv.tmasc_item_id
                                                      , 'SETOR_SEQ' ) setor_seq
              , pdv.empr_id
           INTO v_opp
               ,v_setor_seq
               ,v_empr_id 
           FROM titens_pdv itpdv
               ,titens_comercial itcm
               ,tpedidos_venda pdv
         WHERE itpdv.pdv_id  = pdv.id
           AND itpdv.itcm_id = itcm.id
           AND itpdv.id      = pi_itpdv_id;
           
      EXCEPTION
        WHEN NO_DATA_FOUND THEN
           v_opp       := NULL;
           v_setor_seq := NULL;
           v_empr_id   := NULL;
           
      END;   
            
      IF ( v_opp         IS NOT NULL ) AND         
         ( v_setor_seq   IS NOT NULL ) AND 
         ( v_empr_id     IS NOT NULL ) THEN
         
         ---GERA DADOS TEMPORARIOS COM A ESTRUTURA AGRUPADA 
         BEGIN 
            SULMAQ_AGRUPA_ITENS.INSERE_WG_FSULMAQ_COM008 ( v_empr_id
                                                         , v_opp
                                                         , v_setor_seq 
                                                         , 'CONSULTA'
                                                         , 0);
                                                         
         END;
         
         -- verifica se algum item filho nao foi atendido
         DECLARE
           V_QTDE NUMBER;      
         BEGIN
              
            FOR CUR IN(SELECT *
                         FROM wg_fsulmaq_com008 wgagrp
                       WHERE wgagrp.itpdv_id_nvl_1     = pi_itpdv_id
                         AND wgagrp.nivel              = 3)
            LOOP
            
               SELECT SUM(wgitnf.qtde)
                 INTO v_qtde 
                 FROM wg_titens_nfs wgitnf
               WHERE wgitnf.itpdv_id = cur.itpdv_id_nvl_3
                 AND selecionado = 1;
              
               IF (NVL(cur.qtde_sldo,0) - NVL(v_qtde,0)) > 0 THEN
                  v_faturado := 0;
                  EXIT; 
               END IF;
            
            END LOOP;
            
         EXCEPTION
           WHEN NO_DATA_FOUND THEN 
             v_faturado := 1;
         END;
         
      END IF; 
      
      RETURN v_faturado;
   END;   
   FUNCTION RETORNA_ITPDV_FAT(PI_ITPDV_ID IN TITENS_PDV.ID%TYPE)
   RETURN TITENS_PDV.ID%TYPE
   IS
      /*******************************************************
      Informa o item expedi??o 3 nivel retorna item faturado 1 
      *******************************************************/
      v_opp       tsulmaq_vinc_pdv.num_opp%TYPE;
      v_setor_seq tsulmaq_vinc_pdv.setor_seq%TYPE; 
      v_itpdv_id  titens_pdv.id%TYPE :=  NULL;
   BEGIN
      BEGIN
         
         v_opp := FOCCO3I_UTIL.RETORNA_SELECT_DINAMICO('SELECT oportunidade
                                                          FROM sdi_listas_fabricacao 
                                                        WHERE itpdv_id= '||pi_itpdv_id);
         v_setor_seq := FOCCO3I_UTIL.RETORNA_SELECT_DINAMICO('SELECT setor_seq
                                                                FROM sdi_listas_fabricacao 
                                                              WHERE itpdv_id= '||pi_itpdv_id);
      END;
      
      IF (v_opp       IS NOT NULL) AND       
         (v_setor_seq IS NOT NULL) THEN
      
         SELECT itpdv_id
           INTO v_itpdv_id
           FROM tsulmaq_vinc_pdv
         WHERE num_opp = v_opp 
           AND setor_seq = v_setor_seq;  
          
      END IF;
      
      RETURN v_itpdv_id;
   EXCEPTION
     WHEN NO_DATA_FOUND THEN
       RETURN NULL;   
   END;
      
   
   PROCEDURE GRAVA_TITENS_PLC_LOTE ( p_itpdv_id      IN  titens_pdv.id%TYPE
                                   , p_ite_lote_id   IN  titens_plc_lote.id%TYPE
                                   , p_qtde          IN  titens_pdv.qtde%TYPE 
                                   , p_plc_id        IN  TCARGAS.ID%TYPE
                                   , p_empr_id       IN  TEMPRESAS.ID%TYPE
                                   , po_erro         OUT VARCHAR2) 
   IS
     /********************************************
     Rotina copiada do FPDV0210_CARGA para gerar 
     a titens_plc_lote 
     ********************************************/
     v_itplc_id          titens_plc.id%TYPE;
     v_itempr_id         titens_comercial.itempr_id%TYPE;
     v_itestq_id         titens_estoque.id%TYPE;
     v_empr_id           titens_empr.empr_id%TYPE;
     v_item_id           titens_empr.item_id%TYPE;
     v_almox_id          titens_pdv.almox_id%TYPE;
     v_tmasc_item_id     titens_pdv.tmasc_item_id%TYPE;
     v_lote_id_fifo      titens_lote.id%TYPE;
     v_item_lote         titens_lote.id%TYPE;
   
     v_cod_almox         talmoxarifados.cod_almox%TYPE;
     v_cod_lote_fifo     tlotes.cod_lote%TYPE;
     v_indic_estq_lote   titens_estoque.indic_estq_lote%TYPE;
     v_qtde_lote         titens_plc_lote.qtde%TYPE;

     v_qtde_necessaria   NUMBER;
     v_qtde_saldo_lote   NUMBER;
     
     v_qtde_comercial    NUMBER;
     v_fator_conversao   NUMBER;
    

     v_existe            NUMBER := 0;
   BEGIN

      IF p_plc_id IS NOT NULL THEN
          
         v_fator_conversao := FOCCO3I_PEDIDO.RETORNA_QTDE_CORRIGIDA( pi_empr_id  => P_EMPR_ID
                                                                   , pi_itpdv_id => p_itpdv_id
                                                                   , pi_qtde     => 1
                                                                   , pi_retorno  => 'PDV'
                                                                   );
         BEGIN
            SELECT itempr.empr_id
                 , itpdv.almox_id
                 , almox.cod_almox
                 , itcm.itempr_id
                 , itestq.id
                 , itempr.item_id
                 , itpdv.tmasc_item_id
              INTO v_empr_id
                 , v_almox_id
                 , v_cod_almox
                 , v_itempr_id
                 , v_itestq_id
                 , v_item_id
                 , v_tmasc_item_id
              FROM titens_pdv         itpdv
                 , titens_comercial   itcm
                 , titens_empr        itempr
                 , titens_estoque     itestq
                 , talmoxarifados     almox
             WHERE itpdv.itcm_id   = itcm.id
               AND itcm.itempr_id  = itempr.id
               AND itcm.itempr_id  = itestq.itempr_id
               AND itpdv.almox_id  = almox.id
               AND itpdv.id        = p_itpdv_id;
         EXCEPTION
            WHEN no_data_found THEN
               v_empr_id       := NULL;
               v_almox_id      := NULL;
               v_cod_almox     := NULL;
               v_itempr_id     := NULL;
               v_itestq_id     := NULL;
               v_item_id       := NULL;
               v_tmasc_item_id := NULL;
         END;

         -- verifica se o item controla lote.
         BEGIN
            SELECT indic_estq_lote
              INTO v_indic_estq_lote
              FROM titens_estq_conf
             WHERE tmasc_item_id = v_tmasc_item_id;
         EXCEPTION
            WHEN no_data_found THEN
               BEGIN
                  SELECT indic_estq_lote
                    INTO v_indic_estq_lote
                    FROM titens_estoque
                   WHERE itempr_id = v_itempr_id;
               EXCEPTION
                  WHEN no_data_found THEN
                     v_indic_estq_lote := 0;
               END;
         END;

         BEGIN
            SELECT id
              INTO v_itplc_id
              FROM titens_plc
             WHERE plc_id   = P_plc_id
               AND itpdv_id = p_itpdv_id;
         EXCEPTION
            WHEN others THEN
               v_itplc_id := NULL;
         END;

         v_qtde_saldo_lote := p_qtde;
         v_item_lote       := p_ite_lote_id;

         IF v_indic_estq_lote = 1 THEN

            IF NVL(v_item_lote, 0) <> 0 THEN
   
               SELECT lot_id
                    , l.cod_lote
                 INTO v_lote_id_fifo
                    , v_cod_lote_fifo
                 FROM titens_lote il
                    , tlotes l
               WHERE il.lot_id = l.id
                 AND il.id = v_item_lote;
                 

               BEGIN
                  SELECT 1
                    INTO v_existe
                    FROM titens_plc_lote 
                   WHERE itplc_id    = v_itplc_id
                     AND ite_lote_id = v_item_lote;
               EXCEPTION
                  WHEN others THEN
                     v_existe := 0;
               END;

               BEGIN    
                  --Sol.229497
                  v_qtde_comercial := v_qtde_saldo_lote * v_fator_conversao;
                  
                                    
                  IF v_existe = 0 THEN
                     INSERT INTO titens_plc_lote ( id
                                                 , lote
                                                 , qtde
                                                 , qtde_corrigida
                                                 , fator_conversao
                                                 , itplc_id
                                                 , ite_lote_id )
                                          VALUES ( seq_id_titens_plc_lote.NEXTVAL
                                                 , v_cod_lote_fifo
                                                 , v_qtde_comercial
                                                 , v_qtde_saldo_lote
                                                 , v_fator_conversao
                                                 , v_itplc_id
                                                 , v_item_lote                                                  
                                                 );
                  ELSE
                     UPDATE titens_plc_lote
                        SET qtde_corrigida = qtde_corrigida + v_qtde_saldo_lote
                      WHERE itplc_id       = v_itplc_id
                        AND ite_lote_id    = v_item_lote;
                        
                     --Sol.229497   
                     UPDATE titens_plc_lote
                        SET qtde           = ROUND(qtde_corrigida * v_fator_conversao, 4)                          
                      WHERE itplc_id       = v_itplc_id
                        AND ite_lote_id    = v_item_lote;
                  END IF;
               EXCEPTION
                  WHEN OTHERS THEN
                     PO_ERRO := 'Erro ao salvar na tabela (TITENS_PLC_LOTE)!' || CHR(10) || CHR(10) || SQLERRM;
                     RETURN;
               END;
            END IF;
         ELSE
            --v_lote_id_fifo    := 0;
            --v_qtde_saldo_lote := v_qtde_necessaria;
            BEGIN
               SELECT 1
                 INTO v_existe
                 FROM titens_plc_lote 
                WHERE itplc_id = v_itplc_id;
            EXCEPTION
               WHEN others THEN
                  v_existe := 0;
            END;

            BEGIN                                        
               --Sol.229497
               v_qtde_comercial := v_qtde_saldo_lote * v_fator_conversao;               
               
               
               IF v_existe = 0 THEN
                  INSERT INTO titens_plc_lote ( id
                                              , lote
                                              , qtde
                                              , qtde_corrigida
                                              , fator_conversao
                                              , itplc_id                                               
                                              )
                                       VALUES ( seq_id_titens_plc_lote.NEXTVAL
                                              , NULL
                                              , v_qtde_comercial
                                              , v_qtde_saldo_lote
                                              , v_fator_conversao
                                              , v_itplc_id 
                                              );
               ELSE
                  UPDATE titens_plc_lote
                     SET qtde_corrigida = qtde_corrigida + v_qtde_saldo_lote
                   WHERE itplc_id = v_itplc_id;
                  
                  --Sol.229497
                  UPDATE titens_plc_lote
                     SET qtde     = ROUND(qtde_corrigida * v_fator_conversao, 4)                       
                   WHERE itplc_id = v_itplc_id;
               END IF;
            EXCEPTION
               WHEN OTHERS THEN
                  PO_ERRO := 'Erro ao salvar na tabela (TITENS_PLC_LOTE).' || CHR(10) || SQLERRM;
                  RETURN;
            END;
         END IF;


      END IF;
   END;

   PROCEDURE LEITURA_ETIQ( pi_empr_id IN  TEMPRESAS.ID%TYPE
                         , pi_plc_id  IN  TCARGAS.ID%TYPE
                         , pi_pdv_id  IN  TPEDIDOS_VENDA.ID%TYPE
                         , pi_volume  IN  TVOLUME_CARGA.VOLUME%TYPE
                         , pi_leitura IN  VARCHAR2
                         , po_erro    OUT VARCHAR2
                         ) IS 
     
      v_itempr_id      TITENS_EMPR.ID%TYPE;      
      v_tmasc_item_id  TMASC_ITEM.ID%TYPE;
      v_qtde           NUMBER;
      v_etiq_id        TLEITURAS_ETIQ.ID%TYPE;
      v_cod_item       TITENS.COD_ITEM%TYPE;
      v_num_pedido     TPEDIDOS_VENDA.NUM_PEDIDO%TYPE;
      v_qtde_rest      TCONF_ITPLC.QTDE_REST%TYPE;
      v_ite_lote_id    TITENS_LOTE.ID%TYPE;
      v_itpdv_id       TITENS_PDV.ID%TYPE;
      v_qtde_sldo      TITENS_PDV.QTDE_SLDO%TYPE;
      v_itplc_id       TITENS_PLC.ID%TYPE;
      v_ja_fat         NUMBER(1);
      v_existe         NUMBER(1);

      PROCEDURE VALIDA_LOTE_E_QTDES( pi_empr_id        IN TEMPRESAS.ID%TYPE
                                   , pi_itpdv_id       IN TITENS_PDV.ID%TYPE
                                   , pi_itempr_id      IN TITENS_EMPR.ID%TYPE
                                   , pi_tmasc_item_id  IN TMASC_ITEM.ID%TYPE
                                   , pi_ite_lote_id    IN TITENS_LOTE.ID%TYPE
                                   , pi_qtde           IN NUMBER
                                   , po_erro          OUT VARCHAR2
                                   ) IS

         v_sld_estq    TCONF_ITPLC.QTDE_SALDO%TYPE;
         v_qtde        TMOV_ESTQ.QTDE%TYPE;
         v_tpnf_id     TTIPOS_NF.ID%TYPE;
         v_estoque     TTIPOS_NF.ESTOQUE%TYPE;
         v_cod_almox   TALMOXARIFADOS.COD_ALMOX%TYPE;
         v_ac_qtde_neg TITENS_ESTOQUE.AC_QTDE_NEG%TYPE;
         v_estq_neg    NUMBER(1);

      BEGIN
         v_estq_neg := FOCCO3I_UTIL.RETORNA_PARAMETRO('ESTOQUE', 'VLR_NEG', pi_empr_id, NULL);

         BEGIN
            SELECT 1
              INTO v_existe
              FROM titens_engenharia iteng
                 , titens_comercial itcm
             WHERE itcm.itempr_id     = pi_itempr_id
               AND iteng.tp_estrutura = 'C'
               AND iteng.itempr_id    = itcm.itempr_id;

            --se o item for comercial nao continua o processo de validação
            RETURN;
         EXCEPTION
            WHEN NO_DATA_FOUND THEN
               NULL;
         END;

         BEGIN
            SELECT almox.cod_almox
              INTO v_cod_almox
              FROM talmoxarifados almox
                 , titens_pdv itpdv
             WHERE itpdv.id = pi_itpdv_id
               AND almox.id = itpdv.almox_id;
         EXCEPTION
            WHEN NO_DATA_FOUND THEN
               v_cod_almox := NULL;
         END;

         IF (v_estq_neg = 4) THEN
            BEGIN
               SELECT conf.ac_qtde_neg
                 INTO v_ac_qtde_neg
                 FROM titens_estoque itestq
                    , titens_estq_conf conf
                WHERE itestq.id          = conf.itestq_id
                  AND itestq.itempr_id   = pi_itempr_id
                  AND conf.tmasc_item_id = pi_tmasc_item_id;
            EXCEPTION
               WHEN NO_DATA_FOUND THEN
                  BEGIN
                     SELECT ac_qtde_neg
                       INTO v_ac_qtde_neg
                       FROM titens_estoque itestq
                      WHERE itestq.itempr_id = pi_itempr_id;
                  EXCEPTION
                     WHEN NO_DATA_FOUND THEN
                        v_ac_qtde_neg := 0;
                  END;
            END;
         END IF;

         IF pi_ite_lote_id IS NOT NULL THEN
            v_qtde := 1;
         ELSIF v_cod_almox IS NULL THEN
            /* Busca a quantidade ja conferida do item e soma a quntidade a ser conferida */
            BEGIN
               SELECT SUM(qtde) + NVL(pi_qtde, 0)
                 INTO v_qtde
                 FROM (SELECT NVL(SUM(NVL(conf.qtde_saldo, 0) - NVL(itpdv.qtde_canc, 0)), 0) qtde
                         FROM tconf_itplc      conf
                            , tpedidos_venda   pdv
                            , titens_pdv       itpdv
                            , ttipos_nf        tpnf
                            , titens_comercial itcm
                            , titens_plc       itplc
                        WHERE itcm.itempr_id              = pi_itempr_id
                          AND itpdv.itcm_id               = itcm.id
                          AND pdv.id                     <> pi_pdv_id
                          AND pdv.id                      = itpdv.pdv_id
                          AND pdv.empr_id                 = pi_empr_id
                          AND pdv.pos_pdv                 = 'PE'
                          AND tpnf.id                     = itpdv.tpnf_id
                          AND tpnf.estoque                = 'BA'
                          AND itplc.itpdv_id              = itpdv.id
                          AND itplc.plc_id                = pi_plc_id
                          AND conf.itplc_id               = itplc.id
                          AND conf.atendido               = 0
                          AND NVL(itpdv.tmasc_item_id, 0) = NVL(pi_tmasc_item_id, 0)
                       UNION
                       SELECT NVL(SUM(NVL(conf.qtde_saldo, 0) - NVL(itpdv.qtde_canc, 0)), 0)
                         FROM tconf_itplc      conf
                            , tpedidos_venda   pdv
                            , titens_pdv       itpdv
                            , ttipos_nf        tpnf
                            , titens_comercial itcm
                            , titens_plc       itplc
                        WHERE itcm.itempr_id              = pi_itempr_id
                          AND itpdv.itcm_id               = itcm.id
                          AND pdv.id                      = pi_pdv_id
                          AND pdv.id                      = itpdv.pdv_id
                          AND pdv.empr_id                 = pi_empr_id
                          AND pdv.pos_pdv                 = 'PE'
                          AND tpnf.id                     = itpdv.tpnf_id
                          AND tpnf.estoque                = 'BA'
                          AND itplc.itpdv_id              = itpdv.id
                          AND itplc.plc_id                = pi_plc_id
                          AND conf.itplc_id               = itplc.id
                          AND conf.atendido               = 0
                          AND NVL(itpdv.tmasc_item_id, 0) = NVL(pi_tmasc_item_id, 0));
            EXCEPTION
               WHEN OTHERS THEN
                  v_qtde := 0;
            END;
         ELSE
            /* Busca a quantidade ja conferida do item e soma a quntidade a ser conferida */
            BEGIN
               SELECT SUM(q.qtde) + NVL(pi_qtde, 0)
                 INTO v_qtde
                 FROM (SELECT NVL(SUM(NVL(conf.qtde_saldo, 0) - NVL(itpdv.qtde_canc, 0)), 0) qtde
                         FROM talmoxarifados   almox
                            , tconf_itplc      conf
                            , tpedidos_venda   pdv
                            , titens_pdv       itpdv
                            , ttipos_nf        tpnf
                            , titens_comercial itcm
                            , titens_plc       itplc
                        WHERE almox.cod_almox             = v_cod_almox
                          AND itpdv.almox_id              = almox.id
                          AND itcm.itempr_id              = pi_itempr_id
                          AND itpdv.itcm_id               = itcm.id
                          AND pdv.id                     <> pi_pdv_id
                          AND pdv.id                      = itpdv.pdv_id
                          AND pdv.empr_id                 = pi_empr_id
                          AND pdv.pos_pdv                 = 'PE'
                          AND tpnf.id                     = itpdv.tpnf_id
                          AND tpnf.estoque                = 'BA'
                          AND itplc.itpdv_id              = itpdv.id
                          AND itplc.plc_id                = pi_plc_id
                          AND conf.itplc_id               = itplc.id
                          AND conf.atendido               = 0
                          AND NVL(itpdv.tmasc_item_id, 0) = NVL(pi_tmasc_item_id, 0)
                       UNION
                       SELECT NVL(SUM(conf.qtde_lida), 0) qtde
                         FROM talmoxarifados   almox
                            , tconf_itplc      conf
                            , tpedidos_venda   pdv
                            , titens_pdv       itpdv
                            , ttipos_nf        tpnf
                            , titens_comercial itcm
                            , titens_plc       itplc
                        WHERE almox.cod_almox             = v_cod_almox
                          AND itpdv.almox_id              = almox.id
                          AND itcm.itempr_id              = pi_itempr_id
                          AND itpdv.itcm_id               = itcm.id
                          AND pdv.id                      = pi_pdv_id
                          AND pdv.id                      = itpdv.pdv_id
                          AND pdv.empr_id                 = pi_empr_id
                          AND pdv.pos_pdv                 = 'PE'
                          AND tpnf.id                     = itpdv.tpnf_id
                          AND tpnf.estoque                = 'BA'
                          AND itplc.itpdv_id              = itpdv.id
                          AND itplc.plc_id                = pi_plc_id
                          AND conf.itplc_id               = itplc.id
                          AND conf.atendido               = 0
                          AND NVL(itpdv.tmasc_item_id, 0) = NVL(pi_tmasc_item_id, 0)) q;
            EXCEPTION
               WHEN OTHERS THEN
                  v_qtde := 0;
            END;
         END IF;

         BEGIN
            SELECT FOCCO3I_ESTOQUE.RETORNA_SALDO( itempr.id
                                                , itempr.item_id
                                                , v_cod_almox
                                                , TO_CHAR(SYSDATE, 'DD/MM/RRRR')
                                                , 'NAO'
                                                , pi_tmasc_item_id
                                                , NULL
                                                , pi_ite_lote_id
                                                , NULL
                                                , NULL
                                                , 1
                                                , 1
                                                )
              INTO v_sld_estq
              FROM titens_empr itempr
             WHERE itempr.id = pi_itempr_id;
         EXCEPTION
            WHEN OTHERS THEN
               po_erro :=
                     'Erro ao buscar o saldo. Motivo=>'
                  || DBMS_UTILITY.format_error_stack
                  || DBMS_UTILITY.format_error_backtrace;
               RETURN;
         END;

         IF    (    (v_sld_estq - v_qtde < 0)
                AND (v_estq_neg = 1))
            OR (    (v_sld_estq - v_qtde < 0)
                AND (v_ac_qtde_neg = 0)) THEN
            po_erro := 'Quantidade não disponível em estoque para este lote!';
            RETURN;
         END IF;
      EXCEPTION
         WHEN OTHERS THEN
            po_erro :=
                  'Erro ao criticar quantidades lidas. Motivo=>'
               || DBMS_UTILITY.format_error_stack
               || DBMS_UTILITY.format_error_backtrace;
            RETURN;
      END VALIDA_LOTE_E_QTDES;

      PROCEDURE CONFERE_ITEM( pi_itplc_id  IN TITENS_PLC.ID%TYPE
                            , pi_etiq_id   IN TLEITURAS_ETIQ.ID%TYPE
                            , pi_qtde      IN TITENS_PLC.QTDE%TYPE
                            , po_erro     OUT VARCHAR2
                            ) IS

         v_existe           NUMBER(1);
         v_id_vol           TVOLUME_CARGA.ID%TYPE;
         v_confitplc_id     TCONF_ITPLC.ID%TYPE;
         v_confitplc_vol_id TCONF_ITPLC_VOL.ID%TYPE;

      BEGIN
         BEGIN
            SELECT id
              INTO v_id_vol
              FROM tvolume_carga
            WHERE volume = pi_volume
              AND plc_id = pi_plc_id;
         EXCEPTION
            WHEN NO_DATA_FOUND THEN 
               BEGIN
                  SELECT seq_id_tvolume_carga.NEXTVAL
                    INTO v_id_vol
                    FROM DUAL;

                  INSERT INTO tvolume_carga
                            ( id           
                            , faturado    
                            , etiqueta    
                            , peso_bruto  
                            , itcm_id     
                            , plc_id      
                            , volume
                            )
                     VALUES ( v_id_vol
                            , 0
                            , 1
                            , NULL
                            , NULL
                            , pi_plc_id
                            , pi_volume
                            );
               EXCEPTION
                  WHEN OTHERS THEN 
                     po_erro := 'Erro ao inserir dados na tabela TVOLUME_CARGA. Motivo =>'
                                ||DBMS_UTILITY.FORMAT_ERROR_STACK||DBMS_UTILITY.FORMAT_ERROR_BACKTRACE;
                     RETURN;
               END; 
         END;   

         BEGIN 
            SELECT id 
              INTO v_confitplc_id
              FROM tconf_itplc
             WHERE itplc_id = pi_itplc_id;
         EXCEPTION
            WHEN NO_DATA_FOUND THEN 
               v_confitplc_id := NULL;
         END;

         IF v_confitplc_id IS NULL THEN 
            BEGIN 
               SELECT seq_id_tconf_itplc.NEXTVAL
                 INTO v_confitplc_id
                 FROM dual;

               INSERT INTO tconf_itplc
                         ( id
                         , qtde_lida
                         , qtde_atend
                         , atendido
                         , leitura_obr
                         , itplc_id
                         , confitplc_atendido
                         )
                    SELECT v_confitplc_id
                         , NVL(pi_qtde, 0)
                         , itplc.qtde-itplc.qtde_atend
                         , 0
                         , 1
                         , itplc.id
                         , NULL
                      FROM titens_plc itplc
                     WHERE id = pi_itplc_id;
            EXCEPTION
               WHEN OTHERS THEN 
                  po_erro := 'Erro ao inserir dados na tabela TCONF_ITPLC. Motivo =>'
                             ||DBMS_UTILITY.FORMAT_ERROR_STACK||DBMS_UTILITY.FORMAT_ERROR_BACKTRACE;
                  RETURN;   
            END;
         ELSE          
            UPDATE tconf_itplc
               SET qtde_lida = NVL(qtde_lida, 0) + NVL(pi_qtde, 0)  
             WHERE id = v_confitplc_id;
         END IF;

         BEGIN
            SELECT id
              INTO v_confitplc_vol_id
              FROM tconf_itplc_vol
             WHERE confitplc_id  = v_confitplc_id
               AND volumecarg_id = v_id_vol;

            UPDATE tconf_itplc_vol
               SET qtde = NVL(qtde, 0) + NVL(pi_qtde, 0)
             WHERE id = v_confitplc_vol_id;
         EXCEPTION
            WHEN NO_DATA_FOUND THEN 
               BEGIN
                  SELECT seq_id_tconf_itplc_vol.nextval
                    INTO v_confitplc_vol_id
                    FROM DUAL;

                  INSERT INTO tconf_itplc_vol
                            ( id  
                            , qtde   
                            , volumecarg_id
                            , confitplc_id)
                     VALUES ( v_confitplc_vol_id
                            , NVL(pi_qtde, 0)  
                            , v_id_vol 
                            , v_confitplc_id
                            );
               EXCEPTION
                  WHEN OTHERS THEN 
                     po_erro := 'Erro ao inserir dados na tabela TCONF_ITPLC_VOL. Motivo =>'
                                ||DBMS_UTILITY.FORMAT_ERROR_STACK||DBMS_UTILITY.FORMAT_ERROR_BACKTRACE;
                     RETURN;        
               END;
         END;

         IF pi_etiq_id IS NOT NULL THEN 
            BEGIN
               SELECT 1
                 INTO v_existe
                 FROM tsulmaq_leituras_etiq
                WHERE tleit_etiq_id = pi_etiq_id
                  AND ROWNUM        = 1;
            EXCEPTION
              WHEN NO_DATA_FOUND THEN 
                 INSERT INTO tsulmaq_leituras_etiq
                           ( id
                           , tleit_etiq_id
                           , confitvol_id
                           )
                    VALUES ( seq_id_tsulmaq_leituras_etiq.NEXTVAL
                           , pi_etiq_id
                           , v_confitplc_vol_id
                           );
            END;
         END IF;

         BEGIN
            SELECT 1
              INTO v_existe
              FROM tsulmaq_vol_carga
             WHERE volumecarg_id = v_id_vol;
         EXCEPTION
            WHEN NO_DATA_FOUND THEN  
               BEGIN 
                  INSERT INTO tsulmaq_vol_carga
                            ( id
                            , volumecarg_id
                            , peso
                            , box
                            , largura
                            , comprimento
                            , altura
                            , sit_vol
                            )
                     VALUES ( seq_id_tsulmaq_vol_carga.NEXTVAL
                            , v_id_vol
                            , NULL
                            , NULL
                            , NULL
                            , NULL
                            , NULL
                            , 'A'
                            );
               EXCEPTION
                  WHEN OTHERS THEN
                     po_erro := 'Erro ao inserir dados na tabela TSULMAQ_VOL_CARGA. Motivo =>'
                                ||DBMS_UTILITY.FORMAT_ERROR_STACK||DBMS_UTILITY.FORMAT_ERROR_BACKTRACE;
                     RETURN;
               END;
         END;
      EXCEPTION
         WHEN OTHERS THEN 
            po_erro := 'Erro ao gerar volumes (SULMAQ_AGRUPA_ITENS.CONFERE_ITEM). Motivo =>'
                       ||DBMS_UTILITY.FORMAT_ERROR_STACK||DBMS_UTILITY.FORMAT_ERROR_BACKTRACE;
            RETURN; 
      END CONFERE_ITEM;

      PROCEDURE F3I_REALIZA_CONFERENCIA ( pi_itempr_id     IN TITENS_EMPR.ID%TYPE
                                        , pi_tmasc_item_id IN TMASC_ITEM.ID%TYPE
                                        , pi_pdv_id        IN TPEDIDOS_VENDA.ID%TYPE
                                        , pi_qtde_leitura  IN NUMBER
                                        ) IS

         v_qtde_conferida TCONF_ITPLC.QTDE_ATEND%TYPE;
         v_qtde_restante  TCONF_ITPLC.QTDE_REST%TYPE;
         v_desc_item      VARCHAR2(50);
         v_num_pedido     TPEDIDOS_VENDA.NUM_PEDIDO%TYPE;
         v_qtde           TCONF_ITPLC.QTDE_LIDA%TYPE;
         v_qtde_tot_conf  NUMBER := 0;
         v_aux            NUMBER := 0;
         
         v_erro           VARCHAR2(4000);
         e_erro_validacao EXCEPTION;

         --Verifica se o item da etiqueta existe no Pedido de Venda
         FUNCTION F3I_ITEM_EXISTE_NO_PDV ( pi_itempr_id     IN TITENS_EMPR.ID%TYPE
                                         , pi_tmasc_item_id IN TMASC_ITEM.ID%TYPE
                                         , pi_pdv_id        IN TPEDIDOS_VENDA.ID%TYPE
                                         ) RETURN BOOLEAN IS

            v_existe NUMBER(1);

         BEGIN
            BEGIN
               SELECT 1
                 INTO v_existe
                 FROM titens_pdv       itpdv
                    , titens_comercial itcm
                WHERE itpdv.itcm_id               = itcm.id
                  AND itcm.itempr_id              = pi_itempr_id
                  AND NVL(itpdv.tmasc_item_id, 0) = NVL(pi_tmasc_item_id, 0)
                  AND itpdv.pdv_id                = pi_pdv_id
                  AND ROWNUM                      = 1;

               RETURN TRUE;
            EXCEPTION
               WHEN NO_DATA_FOUND THEN
                  RETURN FALSE;
            END;
         END F3I_ITEM_EXISTE_NO_PDV;

         --Retorna a quantidade de saldo disponível para o item da etiqueta
         FUNCTION F3I_RETORNA_QTDE_SLDO_ITEM ( pi_itempr_id     IN TITENS_EMPR.ID%TYPE
                                             , pi_tmasc_item_id IN TMASC_ITEM.ID%TYPE
                                             , pi_pdv_id        IN TPEDIDOS_VENDA.ID%TYPE
                                             ) RETURN TITENS_PDV.QTDE_SLDO%TYPE IS

            v_qtde_sldo TITENS_PDV.QTDE_SLDO%TYPE;

         BEGIN
            BEGIN
               SELECT SUM(itpdv.qtde_sldo)
                 INTO v_qtde_sldo
                 FROM titens_pdv       itpdv
                    , titens_comercial itcm
                WHERE itpdv.itcm_id               = itcm.id
                  AND itcm.itempr_id              = pi_itempr_id
                  AND NVL(itpdv.tmasc_item_id, 0) = NVL(pi_tmasc_item_id, 0)
                  AND itpdv.pdv_id                = pi_pdv_id;
            EXCEPTION
               WHEN NO_DATA_FOUND THEN
                  v_qtde_sldo := NULL;
            END;

            RETURN v_qtde_sldo;
         END F3I_RETORNA_QTDE_SLDO_ITEM;

         --Verifica se o item possui conferência
         FUNCTION F3I_ITEM_POSSUI_CONF ( pi_itpdv_id IN TITENS_PDV.ID%TYPE
                                       ) RETURN BOOLEAN IS

            v_existe NUMBER(1);

         BEGIN
            BEGIN
               SELECT 1
                 INTO v_existe
                 FROM tconf_itplc conf
                    , titens_plc  itplc
                WHERE conf.itplc_id  = itplc.id
                  AND itplc.itpdv_id = pi_itpdv_id
                  AND itplc.plc_id   = pi_plc_id;

               RETURN TRUE;
            EXCEPTION
               WHEN NO_DATA_FOUND THEN
                  RETURN FALSE;
            END;
         END F3I_ITEM_POSSUI_CONF;

         --Retorna a quantidade conferida para o item do Pedido
         FUNCTION F3I_RETORNA_QTDE_CONFERIDA ( pi_itpdv_id IN TITENS_PDV.ID%TYPE
                                             ) RETURN TCONF_ITPLC.QTDE_ATEND%TYPE IS

            v_qtde_conferida TCONF_ITPLC.QTDE_ATEND%TYPE;

         BEGIN
            BEGIN
               SELECT conf.qtde_atend
                 INTO v_qtde_conferida
                 FROM tconf_itplc conf
                    , titens_plc  itplc
                WHERE conf.itplc_id  = itplc.id
                  AND itplc.itpdv_id = pi_itpdv_id
                  AND itplc.plc_id   = pi_plc_id;
            EXCEPTION
               WHEN NO_DATA_FOUND THEN
                  v_qtde_conferida := 0;
            END;

            RETURN NVL(v_qtde_conferida, 0);
         END F3I_RETORNA_QTDE_CONFERIDA;

         --Retorna a quantidade restante de conferência para o item do Pedido
         FUNCTION F3I_RETORNA_QTDE_RESTANTE ( pi_itpdv_id IN TITENS_PDV.ID%TYPE
                                            ) RETURN TCONF_ITPLC.QTDE_REST%TYPE IS

            v_qtde_rest TCONF_ITPLC.QTDE_REST%TYPE;

         BEGIN
            BEGIN
               SELECT conf.qtde_rest
                 INTO v_qtde_rest
                 FROM tconf_itplc conf
                    , titens_plc  itplc
                WHERE conf.itplc_id  = itplc.id
                  AND itplc.itpdv_id = pi_itpdv_id
                  AND itplc.plc_id   = pi_plc_id;
            EXCEPTION
               WHEN NO_DATA_FOUND THEN
                  v_qtde_rest := 0;
            END;

            RETURN NVL(v_qtde_rest, 0);
         END F3I_RETORNA_QTDE_RESTANTE;

         --Bloqueia o item do pedido para nenhum outro usuário utilizar o mesmo
         PROCEDURE F3I_BLOQUEIA_ITPDV ( pi_itpdv_id  IN TITENS_PDV.ID%TYPE
                                      , po_erro     OUT VARCHAR2
                                      ) IS
         
            v_existe NUMBER(1);
         
         BEGIN
            BEGIN
               SELECT 1
                 INTO v_existe
                 FROM titens_pdv
                WHERE id = pi_itpdv_id
                  FOR UPDATE NOWAIT;
            EXCEPTION
              WHEN OTHERS THEN
                 po_erro := 'O pedido está bloqueado por outro usuário. Verifique.';
                 RETURN;
            END;
         END F3I_BLOQUEIA_ITPDV;


      BEGIN
         BEGIN
            SELECT DECODE(pi_tmasc_item_id, NULL, cod_item, cod_item||' ('||pi_tmasc_item_id||')')
              INTO v_desc_item
              FROM titens_comercial
             WHERE itempr_id = pi_itempr_id;
         EXCEPTION
            WHEN NO_DATA_FOUND THEN
               v_erro := 'Item não localizado. Verifique.';
               RAISE e_erro_validacao;
         END;

         BEGIN
            SELECT num_pedido
              INTO v_num_pedido
              FROM tpedidos_venda
             WHERE id = pi_pdv_id;
         EXCEPTION
            WHEN NO_DATA_FOUND THEN
               v_erro := 'Pedido não localizado. Verifique.';
               RAISE e_erro_validacao;
         END;

         --Verifica se o item existe no Pedido de Venda
         IF NOT F3I_ITEM_EXISTE_NO_PDV( pi_itempr_id
                                      , pi_tmasc_item_id
                                      , pi_pdv_id
                                      ) THEN
            v_erro := 'O item '||v_desc_item||' não existe no Pedido de Venda '||v_num_pedido||'. Verifique.';
            RAISE e_erro_validacao;
         END IF;

         --Verifica se a quantidade da etiqueta não é superior à quantidade disponível para conferência
         IF pi_qtde_leitura > F3I_RETORNA_QTDE_SLDO_ITEM( pi_itempr_id
                                                        , pi_tmasc_item_id
                                                        , pi_pdv_id
                                                        ) THEN
            v_erro := 'A quantidade da etiqueta do item '||v_desc_item
                    ||' é superior à quantidade de saldo do item no Pedido de Venda '||v_num_pedido||'. Verifique.';
            RAISE e_erro_validacao;
         END IF;

         v_aux := 0;

         --Percorre todos os itens do pedido (LOOP pois os mesmo item/máscara pode estar mais de uma vez no pedido)
         FOR c_ite IN (SELECT itpdv.id itpdv_id
                            , itpdv.qtde_sldo
                         FROM titens_pdv       itpdv
                            , titens_comercial itcm
                        WHERE itpdv.itcm_id               = itcm.id
                          AND itcm.itempr_id              = pi_itempr_id
                          AND NVL(itpdv.tmasc_item_id, 0) = NVL(pi_tmasc_item_id, 0)
                          AND itpdv.pdv_id                = pi_pdv_id
                      )
         LOOP
            v_qtde_conferida := F3I_RETORNA_QTDE_CONFERIDA(c_ite.itpdv_id);
            v_qtde_restante  := F3I_RETORNA_QTDE_RESTANTE (c_ite.itpdv_id);
            
            --Se o item não possui mais saldo não deve processar a conferência
            IF c_ite.qtde_sldo = 0 THEN
               CONTINUE;
            END IF;

            --Se o item foi totalmente conferido não deve prosseguir
            IF F3I_ITEM_POSSUI_CONF(c_ite.itpdv_id) AND v_qtde_restante <= 0 THEN
               CONTINUE;
            END IF;

            --Verifica se o pedido não está bloqueado por outro usuário
            F3I_BLOQUEIA_ITPDV ( c_ite.itpdv_id
                               , v_erro
                               );

            IF v_erro IS NOT NULL THEN
               RAISE e_erro_validacao;
            END IF;

            VALIDA_LOTE_E_QTDES( pi_empr_id
                               , c_ite.itpdv_id
                               , pi_itempr_id
                               , pi_tmasc_item_id
                               , v_ite_lote_id
                               , pi_qtde_leitura
                               , v_erro
                               );

            IF v_erro IS NOT NULL THEN 
               RAISE e_erro_validacao;
            END IF;

            BEGIN
               SELECT id
                 INTO v_itplc_id
                 FROM titens_plc
                WHERE itpdv_id = c_ite.itpdv_id
                  AND plc_id   = pi_plc_id;
            EXCEPTION
               WHEN NO_DATA_FOUND THEN
                  v_erro := 'Não foi localizado o item na carga informada.';
                  RAISE e_erro_validacao;
            END;

            v_qtde := LEAST(c_ite.qtde_sldo, pi_qtde_leitura);

            IF F3I_ITEM_POSSUI_CONF(c_ite.itpdv_id) THEN
               v_qtde := LEAST(v_qtde, v_qtde_restante);
            END IF;

            CONFERE_ITEM( v_itplc_id
                        , v_etiq_id
                        , v_qtde
                        , v_erro
                        );

            IF v_erro IS NOT NULL THEN
               RAISE e_erro_validacao;
            END IF;

            GRAVA_TITENS_PLC_LOTE ( c_ite.itpdv_id
                                  , v_ite_lote_id
                                  , v_qtde
                                  , pi_plc_id
                                  , pi_empr_id
                                  , v_erro
                                  );
  
            IF v_erro IS NOT NULL THEN 
               RAISE e_erro_validacao;
            END IF;

            IF v_etiq_id IS NOT NULL THEN 
               UPDATE tleituras_etiq
                  SET lido_exp = 1
                    , itpdv_id = c_ite.itpdv_id
                    , itplc_id = v_itplc_id
                    , status   = 'CARREGADA'
               WHERE ID = v_etiq_id;
            END IF;
            
            v_aux := 1;
            
            v_qtde_tot_conf := v_qtde_tot_conf + v_qtde;
            
            IF v_qtde_tot_conf = pi_qtde_leitura THEN
               EXIT;
            END IF;
         END LOOP;

         IF v_aux = 0 THEN
            v_erro := 'Conferência não realizada. Verifique se o item tem saldo para conferência e se o mesmo não foi conferido em outros volumes.';
            RAISE e_erro_validacao;
         END IF;

      EXCEPTION
         WHEN e_erro_validacao THEN
            BR_UTL_ERROS.RAISE_ERRO(v_erro);

      END F3I_REALIZA_CONFERENCIA;

   BEGIN
      IF pi_leitura IS NOT NULL THEN
         --Busca dados da etiqueta lida como Item, Máscara, Qtde, Etc.
         RETORNA_ITEMPR_ETIQ( pi_empr_id
                            , pi_leitura
                            , v_itempr_id
                            , v_tmasc_item_id
                            , v_qtde
                            , v_etiq_id
                            , v_ite_lote_id
                            , po_erro
                            );

         IF po_erro IS NOT NULL THEN  
            RETURN;
         END IF;   

         --Realiza o processo de conferência
         F3I_REALIZA_CONFERENCIA ( v_itempr_id
                                 , v_tmasc_item_id
                                 , pi_pdv_id
                                 , v_qtde
                                 );

         IF po_erro IS NOT NULL THEN 
           RETURN;
         END IF;
      END IF;

   END LEITURA_ETIQ;

   PROCEDURE RETORNA_ITEMPR_ETIQ(PI_EMPR_ID       IN  TEMPRESAS.ID%TYPE
                                ,PI_LEITURA       IN  VARCHAR2
                                ,PO_ITEMPR_ID     OUT TITENS_EMPR.ID%TYPE
                                ,PO_TMASC_ITEM_ID OUT TMASC_ITEM.ID%TYPE
                                ,PO_QTDE          OUT NUMBER
                                ,PO_ETIQ_ID       OUT TLEITURAS_ETIQ.ID%TYPE  
                                ,PO_ITE_LOTE_ID   OUT TITENS_LOTE.ID%TYPE  
                                ,PO_ERRO          OUT VARCHAR2)
   IS 
      /*************************************
      ROTINA UTILIZADA PELO FSULMAQ_COM010
      Passa o codeBarra leido retorna o item
      *************************************/
      
      v_qtde                  NUMBER := null;
      v_lido_exp              NUMBER(1);
      V_SEQ_COD               NUMBER;
      V_SEQ_QTDE              NUMBER;
      V_LETIQ_ID              TLEITURAS_ETIQ.ID%TYPE;
      V_LOTE                  TLOTES.COD_LOTE%TYPE;
      V_INDIC_ESTQ_LOTE       NUMBER(1);
      
      v_num_pedido            tpedidos_venda.num_pedido%TYPE;
      V_ITE_LOTE_ID           TITENS_LOTE.ID%TYPE;
      V_COD_ITEM              TITENS.COD_ITEM%TYPE;
      V_TMASC_ITEM_ID         TMASC_ITEM.ID%TYPE;
      V_ITEMPR_ID             TITENS_EMPR.ID%TYPE;
      V_LOTE_ID               TLOTES.ID%TYPE; 


   BEGIN
         --MSG_TAB --:= TPL_RETORNA_PARAMETRO('CONF_ITPDV', 'MSG_TAB', :tempresas.id);
         
      IF PI_LEITURA IS NOT NULL THEN
         BEGIN 
            -- busca code barra na TCAD_COD_BARRA      
             BEGIN 
                SELECT item.cod_item
                  INTO v_cod_item
                  FROM tcod_barra bar
                     , tlin_cod_barra lin
                     , tcad_cod_barra cad
                     , titens item
                     , titens_empr emp
                 WHERE bar.id        = lin.cod_bar_id
                   AND lin.id        = cad.lin_cod_ba_id
                   AND emp.id        = cad.itempr_id
                   AND item.id       = emp.item_id
                   AND cad.cod_barra = pi_leitura
                   AND emp.empr_id   = pi_empr_id;
             EXCEPTION 
                WHEN NO_DATA_FOUND THEN
                   v_cod_item     := NULL;
                  
             END;
             
             -- Busca a Sequencia na TCOMP_COD_BARRA
             BEGIN
                SELECT comp.seq
                  INTO v_seq_cod
                  FROM tcomp_cod_barra comp
                     , tcad_cod_barra cad
                 WHERE cad.empr_id        = pi_empr_id
                   AND cad.cod_barra      = pi_leitura
                   AND comp.lin_cod_ba_id = cad.lin_cod_ba_id
                   AND comp.campo         = 'COD_ITEM';
             EXCEPTION 
                WHEN OTHERS THEN
                   v_seq_cod := 0;
             END;

             -- Busca a Sequencia na TCOMP_COD_BARRA
             BEGIN
                SELECT comp.seq
                  INTO v_seq_qtde 
                  FROM tcomp_cod_barra comp
                     , tcad_cod_barra cad
                 WHERE cad.empr_id        = pi_empr_id
                   AND cad.cod_barra      = pi_leitura
                   AND comp.lin_cod_ba_id = cad.lin_cod_ba_id
                   AND comp.campo         = 'FAT_CONV_VOL';
             EXCEPTION
                WHEN OTHERS THEN
                   v_seq_qtde := 0;
             END;

             IF V_SEQ_COD = 0 AND V_SEQ_QTDE = 0 THEN
                
                -- Tenta ler direto o codigo do item
                BEGIN
                   SELECT ITEMPR.COD_ITEM
                     INTO V_COD_ITEM
                     FROM TITENS_EMPR ITEMPR
                        , TCAD_COD_BARRA CAD
                    WHERE CAD.EMPR_ID = PI_EMPR_ID
                      AND COD_BARRA   = PI_LEITURA
                      AND ITEMPR.ID   = CAD.ITEMPR_ID
                      AND ROWNUM      = 1;  
        
                   V_QTDE      := 1;

                EXCEPTION
                   WHEN OTHERS THEN
                      BEGIN
                         BEGIN               
                            SELECT ITPL.COD_ITEM
                                 , ITPL.ITEMPR_ID
                                 , LOTE.ID LOTE_ID
                                 , L.ID
                                 , LOTE.COD_LOTE
                                 , ITLOTE.ID
                                 , L.LIDO_EXP
                                 , ORD.TMASC_ITEM_ID
                                 , L.QTDE
                              INTO V_COD_ITEM
                                 , V_ITEMPR_ID
                                 , V_LOTE_ID
                                 , V_LETIQ_ID
                                 , V_LOTE
                                 , V_ITE_LOTE_ID
                                 , V_LIDO_EXP
                                 , V_TMASC_ITEM_ID
                                 , V_QTDE
                              FROM TITENS_LOTE           ITLOTE
                                 , TLOTES                LOTE
                                 , TITENS_PLANEJAMENTO   ITPL
                                 , TORDENS               ORD
                                 , TLEITURAS_ETIQ        L
                             WHERE L.COD_BARRA                           = PI_LEITURA
                               AND ORD.ID                                = L.ORDEM_ID
                               AND ITPL.ID                               = ORD.ITPL_ID
                               AND LOTE.COD_LOTE(+)                      = L.COD_BARRA
                               AND ITLOTE.LOT_ID(+)                      = LOTE.ID
                               AND NVL(L.IND_ID,0)                       = 0
                               AND NVL(ITLOTE.ITEMPR_ID, ITPL.ITEMPR_ID) = ITPL.ITEMPR_ID
                               AND ROWNUM                                = 1;
                         EXCEPTION
                            WHEN NO_DATA_FOUND THEN
                               BEGIN
                                  SELECT ITPL.COD_ITEM
                                       , ITPL.ITEMPR_ID
                                       , LOTE.ID LOTE_ID
                                       , L.ID
                                       , LOTE.COD_LOTE
                                       , ITLOTE.ID
                                       , L.LIDO_EXP
                                       , NVL(NVL(ITLOTE.TMASC_ITEM_ID, ORD.TMASC_ITEM_ID),L.TMASC_ITEM_ID)
                                       , L.QTDE
                                    INTO V_COD_ITEM
                                       , V_ITEMPR_ID
                                       , V_LOTE_ID
                                       , V_LETIQ_ID
                                       , V_LOTE
                                       , V_ITE_LOTE_ID
                                       , V_LIDO_EXP
                                       , V_TMASC_ITEM_ID
                                       , V_QTDE
                                    FROM TITENS_LOTE           ITLOTE
                                       , TLOTES                LOTE
                                       , TITENS_PLANEJAMENTO   ITPL
                                       , TORDENS               ORD
                                       , TLEITURAS_ETIQ        L
                                   WHERE L.COD_BARRA                           = PI_LEITURA
                                     AND L.COD_BARRA                           = L.ID
                                     AND ORD.ID(+)                             = L.ORDEM_ID
                                     AND LOTE.ID(+)                            = L.LOTE_ID
                                     AND ITLOTE.LOT_ID(+)                      = LOTE.ID
                                     AND ITPL.ITEMPR_ID                        = L.ITEMPR_ID
                                     AND L.IND_ID                              = 1
                                     AND NVL(ITLOTE.ITEMPR_ID, ITPL.ITEMPR_ID) = ITPL.ITEMPR_ID
                                     AND ROWNUM                                = 1;
                               EXCEPTION
                                 WHEN NO_DATA_FOUND THEN 
                                    RAISE NO_DATA_FOUND;
                               END;
                         END;

                      EXCEPTION
                         WHEN OTHERS THEN
                            V_QTDE := NULL;
                      END;
                      
                      BEGIN
                         SELECT INDIC_ESTQ_LOTE
                           INTO V_INDIC_ESTQ_LOTE
                           FROM TITENS_ESTQ_CONF
                         WHERE TMASC_ITEM_ID = V_TMASC_ITEM_ID;
                      EXCEPTION
                        WHEN NO_DATA_FOUND THEN
                           BEGIN
                              SELECT indic_estq_lote
                                INTO v_indic_estq_lote
                                FROM titens_estoque
                               WHERE itempr_id = v_itempr_id;
                           EXCEPTION
                             WHEN NO_DATA_FOUND THEN
                                V_INDIC_ESTQ_LOTE := 0;
                           END;
                      END;

                      IF V_INDIC_ESTQ_LOTE = 1 AND V_LOTE_ID IS NULL THEN
                         PO_ERRO :='N?o foi dada a entrada na produ??o deste item!';
                         RAISE NO_DATA_FOUND;
                      END IF;
                      
                      IF V_LIDO_EXP = 1 THEN     
                         BEGIN
                            SELECT num_pedido
                              INTO v_num_pedido
                              FROM tpedidos_venda pdv
                                 , titens_pdv itpdv
                                 , tleituras_etiq letq
                             WHERE letq.id        = v_letiq_id 
                               AND letq.itpdv_id  = itpdv.id
                               AND itpdv.pdv_id   = pdv.id;
                         EXCEPTION
                            WHEN NO_DATA_FOUND THEN
                               V_NUM_PEDIDO := NULL;
                         END;    
                         
                         PO_ERRO  := 'Este item ja foi conferido no pedido '||V_NUM_PEDIDO||'.';
                         RAISE NO_DATA_FOUND;   
                      END IF;      
                END;
           
             END IF;
         EXCEPTION 
           WHEN NO_DATA_FOUND THEN 
              NULL;
         END;
      END IF;
          
            
      IF (V_ITEMPR_ID IS NOT NULL) THEN 
         PO_ITEMPR_ID      := V_ITEMPR_ID;    
         PO_TMASC_ITEM_ID  := V_TMASC_ITEM_ID;
         PO_ETIQ_ID        := V_LETIQ_ID;
         PO_QTDE           := V_QTDE;
         PO_ITE_LOTE_ID    := V_ITE_LOTE_ID;
         IF V_LIDO_EXP = 1 THEN     
           PO_ERRO  := 'O codigo de barras informado ja foi lido.';
         ELSE
           PO_ERRO :=  NULL;  
         END IF;
      ELSE
         PO_ITEMPR_ID      := NULL;    
         PO_TMASC_ITEM_ID  := NULL;
         PO_ETIQ_ID        := NULL;
         PO_QTDE           := NULL;
         PO_ITE_LOTE_ID    := NULL;
         PO_ERRO           := 'O codigo de barras informado n?o foi encontrado.';
      END IF;
     
   END;
   PROCEDURE APAGA_TCONF_ITPLC( PI_CONFITPLC_ID  IN  TCONF_ITPLC.ID%TYPE
                              , PI_VOLUME        IN  TVOLUME_CARGA.VOLUME%TYPE
                              , PO_ERRO          OUT VARCHAR2)
   IS   
     /*
     ROTINA UTILIZADA PELO FSULMAQ_COM010
     Reponsavel para apagar a leitura feita 
     */
     
     v_existe      NUMBER(1);
     v_cod_item    titens.cod_item%TYPE;
     v_num_item    titens_pdv.num_item%TYPE;
     v_num_pedido  tpedidos_venda.num_pedido%TYPE;
   BEGIN
      IF PI_CONFITPLC_ID IS NOT NULL THEN 
      
         FOR CUR IN( SELECT plc.carga
                           ,plc.id plc_id
                           ,plc.empr_id
                           ,plc.sit_plc
                           ,volplc.volume
                           ,volplc.faturado
                           ,smqvolplc.sit_vol
                           ,itplc.itpdv_id
                           ,itplc.id itplc_id
                           ,itvol.volumecarg_id
                           ,itvol.qtde qtde_lida_vol
                           ,confitplc.qtde_lida
                       FROm tconf_itplc       confitplc
                           ,titens_plc        itplc
                           ,tconf_itplc_vol   itvol
                           ,tvolume_carga     volplc
                           ,tsulmaq_vol_carga smqvolplc
                           ,tcargas           plc 
                     WHERE itplc.id      = confitplc.itplc_id
                       AND confitplc.id  = itvol.confitplc_id  
                       AND volplc.id     = itvol.volumecarg_id
                       AND plc.id        = itplc.plc_id
                       AND volplc.id     = smqvolplc.volumecarg_id
                       AND confitplc.id  = pi_confitplc_id 
                       AND volplc.volume = pi_volume
                       )
         
         LOOP
         
           IF cur.sit_plc = 'F' THEN 
             PO_ERRO := 'A carga ('||cur.carga||') esta fechada. A leitura n?o pode ser excluida.';
             RETURN;
           END IF;
           
           IF cur.sit_vol = 'F' THEN 
             PO_ERRO := 'O volume ('||cur.volume||') da carga ('||cur.carga||') esta fechado. A leitura n?o pode ser excluida.';
             RETURN;
           END IF;
    
           BEGIN
              SELECT itcm.cod_item
                   , itpdv.num_item
                   , pdv.num_pedido
                INTO v_cod_item   
                   , v_num_item   
                   , v_num_pedido 
                FROM titens_pdv        itpdv
                   , titens_comercial  itcm
                   , tpedidos_venda    pdv
                   , thist_mov_ite_pdv hist
              WHERE hist.itpdv_id  = itpdv.id
                AND itpdv.itcm_id  = itcm.id
                AND itpdv.pdv_id   = pdv.id
                AND hist.itnfs_id  IS NOT NULL
                AND itpdv.id       = cur.ITPDV_ID
                AND hist.itplc_id  = cur.ITPLC_ID
                AND ROWNUM = 1;
            
              po_erro := 'Item ja faturado, n?o pode ser apagado!'||CHR(10)||
                         'Pedido: '||v_num_pedido||chr(10)||
                         'Cod. Item: '||v_cod_item||chr(10)||
                         'Seq: '||v_num_item;
              RETURN;
           EXCEPTION
             WHEN NO_DATA_FOUND THEN
                NULL;
           END;
           
           BEGIN 
              SELECT 1
                INTO v_existe
                FROM tconf_itplc_vol 
              WHERE confitplc_id  = pi_confitplc_id
                AND volumecarg_id <> cur.volumecarg_id
                AND ROWNUM = 1;
           EXCEPTION
             WHEN NO_DATA_FOUND THEN 
                v_existe := 0;
           END;  
           
           IF v_existe = 1 THEN 
           
              UPDATE tconf_itplc
                 SET QTDE_LIDA = (NVL(cur.qtde_lida,0) - NVL(cur.qtde_lida_vol,0))
              WHERE id = pi_confitplc_id; 

   
              GRAVA_TITENS_PLC_LOTE ( cur.itpdv_id
                                    , NULL
                                    , NVL(cur.qtde_lida_vol,0)*-1
                                    , cur.plc_id     
                                    , cur.empr_id    
                                    , po_erro 
                                    ) ;
               IF PO_ERRO IS NOT NULL THEN 
               
                  RETURN;
                 
               END IF;
                                   
               UPDATE tleituras_etiq
                 SET itpdv_id = NULL
                   , itplc_id = NULL
                   , lido_exp = 0
                   , status   = 'GERADA'
               WHERE ID IN(SELECT tleit_etiq_id
                             FROM tconf_itplc_vol confitvol
                                , tsulmaq_leituras_etiq smqetq       
                           WHERE smqetq.confitvol_id     = confitvol.id  
                             AND confitvol.volumecarg_id = cur.volumecarg_id);
                             
               DELETE tconf_itplc_vol
               WHERE volumecarg_id = cur.volumecarg_id;
           
           ELSE
           
              
              DELETE tconf_itplc
              WHERE id = pi_confitplc_id;
              
              DELETE titens_plc_lote
              WHERE itplc_id = cur.itplc_id;
              
              UPDATE tleituras_etiq
                 SET itpdv_id = NULL
                   , itplc_id = NULL
                   , status   = 'GERADA' 
                   , lido_exp = 0
              WHERE itplc_id = cur.itplc_id;
                         
           END IF;
           
           --Se encontrar registro excluir o volume
           BEGIN
              SELECT 1
                INTO v_existe
                FROM tconf_itplc_vol
              WHERE volumecarg_id = cur.volumecarg_id
                AND ROWNUM = 1;
           EXCEPTION
             WHEN NO_DATA_FOUND THEN
         
               DELETE tvolume_carga
               WHERE id = cur.volumecarg_id;
         
           END;
           
         END LOOP;    
      END IF;
   EXCEPTION
     WHEN OTHERS THEN 
       PO_ERRO := 'N?o foi possivel deletar a leitura. Motivo =>'||DBMS_UTILITY.FORMAT_ERROR_STACK||DBMS_UTILITY.FORMAT_ERROR_BACKTRACE;   
   END;   
   PROCEDURE ALTERA_SITUACAO_VOLUME( pi_plc_id  IN  TCARGAS.ID%TYPE
                                   , pi_volume  IN  TVOLUME_CARGA.VOLUME%TYPE
                                   , pi_acao    IN  VARCHAR2
                                   , po_erro    OUT VARCHAR2)
   IS   
     /************************************
     ROTINA UTILIZADA PELO FSULMAQ_COM010
     ************************************/
     v_existe      NUMBER(1);
     v_cod_item    titens.cod_item%TYPE;
     v_num_item    titens_pdv.num_item%TYPE;
     v_num_pedido  tpedidos_venda.num_pedido%TYPE;
   BEGIN
      
      FOR CUR_VOL IN ( SELECT smqvolplc.id smqvolplc_id
                             ,smqvolplc.sit_vol
                             ,volplc.id volumecarg_id 
                             ,volplc.volume
                             ,volplc.faturado
                         FROM tvolume_carga     volplc
                            , tsulmaq_vol_carga smqvolplc
                       WHERE volplc.id     = smqvolplc.volumecarg_id 
                         AND volplc.plc_id = pi_plc_id
                         AND volplc.volume = pi_volume )
      LOOP

          IF PI_ACAO = 'FECHAR'  THEN 
             
             IF cur_vol.sit_vol = 'F' THEN 
                PO_ERRO := 'Volume ja esta fechado!';
                RETURN;
             END IF;
             /*
             BEGIN 
               SELECT 1
                 INTO v_existe
                 FROM tsulmaq_vol_carga
               WHERE id = cur_vol.smqvolplc_id
                 AND peso        IS NOT NULL
                 AND box         IS NOT NULL
                 AND largura     IS NOT NULL
                 AND comprimento IS NOT NULL
                 AND alturar     IS NOT NULL;
             EXCEPTION
               WHEN NO_DATA_FOUND THEN 
                 PO_ERRO := 'Favor verificar se as informa??es adicionais do volume foram corretamente preenchidas.';
                 RETURN;
             END;
             
            */
            
             UPDATE tsulmaq_vol_carga
                set sit_vol = 'F'
             WHERE id = cur_vol.smqvolplc_id; 
          
          ELSIF PI_ACAO = 'ABRIR'  THEN 
             
             IF cur_vol.sit_vol = 'A' THEN 
                PO_ERRO := 'Volume ja esta aberto!';
                RETURN;
             END IF;
             
              
             FOR CUR IN( SELECT plc.carga
                               ,plc.id plc_id
                               ,plc.sit_plc
                               ,itplc.itpdv_id
                               ,itplc.id itplc_id
                               ,itvol.volumecarg_id
                           FROM tconf_itplc       confitplc
                               ,titens_plc        itplc
                               ,tconf_itplc_vol   itvol
                               ,tcargas           plc 
                         WHERE itplc.id            = confitplc.itplc_id
                           AND confitplc.id        = itvol.confitplc_id  
                           AND itvol.volumecarg_id = cur_vol.volumecarg_id
                           AND plc.id              = itplc.plc_id )
             LOOP
             
                IF cur.sit_plc = 'F' THEN 
                  PO_ERRO := 'A carga ('||cur.carga||') esta fechada. O volume n?o pode ser aberto.';
                  RETURN;
                END IF;
               
                BEGIN
                   SELECT itcm.cod_item
                        , itpdv.num_item
                        , pdv.num_pedido
                     INTO v_cod_item   
                        , v_num_item   
                        , v_num_pedido 
                     FROM titens_pdv        itpdv
                        , titens_comercial  itcm
                        , tpedidos_venda    pdv
                        , thist_mov_ite_pdv hist
                   WHERE hist.itpdv_id  = itpdv.id
                     AND itpdv.itcm_id  = itcm.id
                     AND itpdv.pdv_id   = pdv.id
                     AND hist.itnfs_id  IS NOT NULL
                     AND itpdv.id       = cur.ITPDV_ID
                     AND hist.itplc_id  = cur.ITPLC_ID
                     AND ROWNUM = 1;
                
                  po_erro := 'Item ja faturado, o volume n?o pode ser aberto!'||CHR(10)||
                             'Pedido: '||v_num_pedido||chr(10)||
                             'Cod. Item: '||v_cod_item||chr(10)||
                             'Seq: '||v_num_item;
                  RETURN;
                EXCEPTION
                  WHEN NO_DATA_FOUND THEN
                     NULL;
                END;
             
                  
                UPDATE tsulmaq_vol_carga
                   set sit_vol = 'A'
                WHERE id = cur_vol.smqvolplc_id; 
               
             END LOOP;    
          END IF;
      END LOOP;      
   EXCEPTION
     WHEN OTHERS THEN 
       PO_ERRO := 'N?o foi possivel '||pi_acao||' o volume. Motivo =>'||DBMS_UTILITY.FORMAT_ERROR_STACK||DBMS_UTILITY.FORMAT_ERROR_BACKTRACE;   
   END; 
   FUNCTION RETORNA_VOLUME_PLC(PI_PLC_ID IN TCARGAS.ID%TYPE)
   RETURN VARCHAR2
   IS
     /*************************************************
     ROTINA UTILIZADA PELO FSULMAQ_COM010
     Func?o retorna o volume para a carga com base na
     situa??o do volume na TSULMAQ_VOL_CARGA 
     *************************************************/
     
     V_VOLUME    TVOLUME_CARGA.VOLUME%TYPE := NULL;
     V_VOLPLC_ID TVOLUME_CARGA.ID%TYPE;
     V_SIT_VOL   TSULMAQ_VOL_CARGA.SIT_VOL%TYPE;
     V_EXISTE    NUMBER;
   BEGIN
      BEGIN
         SELECT 1
           INTO v_existe
           FROM tcargas
          WHERE id = pi_plc_id;
      EXCEPTION
        WHEN NO_DATA_FOUND THEN 
          v_existe := 0;
      END;
      
      IF v_existe = 1 THEN
         
         BEGIN
            
            SELECT vol.volume
                 , vol.id
                 , sul.sit_vol
              INTO v_volume
                 , v_volplc_id
                 , v_sit_vol
              FROM tvolume_carga     vol
                 , tsulmaq_vol_carga sul
             WHERE vol.id     = sul.volumecarg_id
               --AND vol.plc_id = pi_plc_id;
               AND vol.plc_id in(SELECT PLC_ID_NEW PLC_ID
                                   FROM TSULMAQ_COM013_LOG_TRANSF
                                 WHERE PLC_ID_ANT = pi_plc_id
                                 UNION
                                 SELECT pi_plc_id 
                                   FROM dual );
         EXCEPTION
            WHEN NO_DATA_FOUND THEN 
               v_volume  := 1;
               v_sit_vol := 'A';
            WHEN TOO_MANY_ROWS THEN 
               BEGIN 
                  SELECT vol.volume
                       , vol.id
                       , sul.sit_vol
                    INTO v_volume
                       , v_volplc_id
                       , v_sit_vol
                    FROM tvolume_carga     vol
                       , tsulmaq_vol_carga sul
                   WHERE vol.id      = sul.volumecarg_id
                     AND sul.sit_vol = 'A'
                     AND vol.plc_id  IN(SELECT PLC_ID_NEW PLC_ID
                                          FROM TSULMAQ_COM013_LOG_TRANSF
                                        WHERE PLC_ID_ANT = pi_plc_id
                                        UNION
                                        SELECT pi_plc_id 
                                          FROM dual );
               EXCEPTION
                  WHEN TOO_MANY_ROWS THEN 
                     --Busca o menor volume aberto
                     SELECT MIN(to_number(vol.volume))
                          , 'A'
                       INTO v_volume
                          , v_sit_vol
                       FROM tvolume_carga     vol
                          , tsulmaq_vol_carga sul
                      WHERE vol.id      = sul.volumecarg_id
                        AND sul.sit_vol ='A'
                        AND vol.plc_id IN(SELECT PLC_ID_NEW PLC_ID
                                            FROM TSULMAQ_COM013_LOG_TRANSF
                                          WHERE PLC_ID_ANT = pi_plc_id
                                          UNION
                                          SELECT pi_plc_id 
                                            FROM dual );
               WHEN NO_DATA_FOUND THEN 
                  BEGIN  
                     --Busca o maior volume fechado
                     SELECT MAX(to_number(vol.volume))
                       INTO v_volume
                       FROM tvolume_carga     vol
                          , tsulmaq_vol_carga sul
                      WHERE vol.id      = sul.volumecarg_id
                        AND sul.sit_vol = 'F'
                        AND vol.plc_id in(SELECT PLC_ID_NEW PLC_ID
                                            FROM TSULMAQ_COM013_LOG_TRANSF
                                          WHERE PLC_ID_ANT = pi_plc_id
                                          UNION
                                          SELECT pi_plc_id 
                                            FROM dual );
                    
                     -- Verifica se ha itens na carga para serem conferidos 
                     BEGIN
                       SELECT 'F'
                         INTO v_sit_vol
                         FROM titens_plc itplc
                        WHERE itplc.plc_id in(SELECT PLC_ID_NEW PLC_ID
                                                FROM TSULMAQ_COM013_LOG_TRANSF
                                              WHERE PLC_ID_ANT = pi_plc_id
                                              UNION
                                              SELECT pi_plc_id 
                                                FROM dual )
                          AND NOT EXISTS (SELECT 1
                                            FROM tconf_itplc confplc
                                           WHERE confplc.itplc_id  = itplc.id
                                             AND confplc.qtde_rest = 0)
                          AND ROWNUM = 1;
                     EXCEPTION
                        WHEN NO_DATA_FOUND THEN
                           v_sit_vol := 'T';
                     END;
                  END;
               END;
         END;

         IF v_sit_vol = 'F' THEN
            INC(v_volume);
         END IF; 
      END IF;

      RETURN v_volume;
   END;
   
   FUNCTION RET_DESC_CONFIG(PI_TMASC_ITEM_ID IN TMASC_ITEM.ID%TYPE
                           ,PI_APARTIR       IN NUMBER)
   RETURN VARCHAR2                                                
   IS
     /*****************************************
     FUN??O CRIADA PARA RETORNAR A MASCARA DO
     ITEM IGNORANDO AS CARACTERISTICAS INICIAIS
     ******************************************/
     
     v_mascara tmasc_item.mascara%TYPE;
   BEGIN
      BEGIN 
         SELECT LISTAGG(SEL.RESPOSTA, '#') WITHIN GROUP (ORDER BY SEL.SEQ)
           INTO v_mascara  
           FROM (SELECT SEQ
                      ,  DENSE_RANK() OVER (PARTITION BY CONF.TMASC_ITEM_ID ORDER BY CONF.SEQ) AS RANK
                      ,  CASE
                          WHEN TO_CHAR(CONF.VALOR)    IS NOT NULL THEN TO_CHAR(CONF.VALOR)
                          WHEN TO_CHAR(CONF.TEXTO)    IS NOT NULL THEN TO_CHAR(CONF.TEXTO)
                          WHEN TO_CHAR(VAR.MNEMONICO) IS NOT NULL THEN TO_CHAR(VAR.MNEMONICO)
                         END RESPOSTA
                   FROM TCONFIG_ITENS CONF
                       ,TVARIAVEIS VAR
                 WHERE CONF.TMASC_ITEM_ID = PI_TMASC_ITEM_ID 
                   AND VAR.ID(+) = CONF.TVAR_ID
                   ) SEL
         WHERE RANK >= PI_APARTIR;
     
      EXCEPTION
        WHEN NO_DATA_FOUND THEN 
          V_MASCARA := NULL;
      END;
      RETURN V_MASCARA;         
   END;

   --Leonardo Bolzan - 20/02/2017 - Novo Processo Faturamento por Carga
   PROCEDURE FATURA_CARGA_OPP IS

      /*******************************************************************************
         PROCEDURE FATURA_CARGA_OPP
      --------------------------------------------------------------------------------
         FINALIDADE: *Alterar o processo de faturamento por carga (FFAT0220) para
                     faturar os itens de venda conforme agrupamento de itens
                     (FSULMAQ_COM008) com base nos itens expedição (itens da carga).
                     *Controlar o atendimento dos itens em ambos os pedidos de venda
                     (Pedido Expedição e Pedido FUT).
                     *Controlar a baixa de estoque dos itens expedição.
         MODIFICADO:
           20/02/2017 - Leonardo Bolzan - Criação da Procedure
      *******************************************************************************/

      pi_wgtnfs_id    WG_TNFS_SAIDA.ID%TYPE;
      pi_sessao       NUMBER;
      pi_empr_id      TEMPRESAS.ID%TYPE;

      v_origem_fat    WG_TNFS_SAIDA.ORIGEM_FAT%TYPE;
      v_num_opp       WG_FSULMAQ_COM008.NUM_OPP%TYPE;
      v_vlr_total     WG_FSULMAQ_COM008.VLR_TOTAL%TYPE;
      v_wgitnfs_id    WG_TITENS_NFS.ID%TYPE;
      v_num_linha     WG_TITENS_NFS.NUM_LINHA%TYPE;
      v_qtde_venda    WG_FSULMAQ_COM008.QTDE%TYPE;
      v_vlr_venda     WG_FSULMAQ_COM008.VLR_TOTAL%TYPE;
      v_dt_cotacao    DATE;
      v_moe_id        TPEDIDOS_VENDA.MOE_ID%TYPE;

      v_erro          VARCHAR2(4000);
      e_n_continua    EXCEPTION;
      e_erro_processo EXCEPTION;

      --Retorna a Oportunidade que está sendo faturada
      FUNCTION F3I_RETORNA_OPP ( pi_wgtnfs_id IN WG_TNFS_SAIDA.ID%TYPE
                               ) RETURN WG_FSULMAQ_COM008.NUM_OPP%TYPE IS

         v_itpdv_id_venda TITENS_PDV.ID%TYPE;
         v_num_opp        WG_FSULMAQ_COM008.NUM_OPP%TYPE;

      BEGIN
         SELECT SULMAQ_AGRUPA_ITENS.RETORNA_ITPDV_FAT(wg.itpdv_id)
           INTO v_itpdv_id_venda
           FROM wg_titens_nfs wg
          WHERE wg.wgtnfs_id    = pi_wgtnfs_id
            AND wg.ind_fatura   = 1 
            AND wg.selecionado  = 1
            AND ROWNUM          = 1;

         SELECT SULMAQ_AGRUPA_ITENS.RETORNA_MNEMONICO(itcm.itempr_id, itpdv.tmasc_item_id, 'OPORTUNIDADE')
           INTO v_num_opp
           FROM titens_pdv       itpdv
              , titens_comercial itcm
          WHERE itpdv.itcm_id = itcm.id
            AND itpdv.id      = v_itpdv_id_venda;

         RETURN v_num_opp;
      EXCEPTION
         WHEN NO_DATA_FOUND THEN
            RETURN NULL;
      END F3I_RETORNA_OPP;

      --Atualiza informações da capa da nota fiscal
      PROCEDURE F3I_ATUALIZA_DADOS_CAPA ( pi_wgtnfs_id  IN WG_TNFS_SAIDA.ID%TYPE
                                        , po_erro      OUT VARCHAR2
                                        ) IS

         v_placa         WG_TNFS_SAIDA.PLACA%TYPE;
         v_marca         WG_TNFS_SAIDA.MARCA%TYPE;
         v_vlr_frete     WG_TNFS_SAIDA.VLR_FRETE%TYPE;
         v_vlr_seguro    WG_TNFS_SAIDA.VLR_SEGURO%TYPE;
         v_peso_liq      WG_TNFS_SAIDA.PESO_LIQ%TYPE;
         v_peso_brt      WG_TNFS_SAIDA.PESO_BRT%TYPE;
         v_qtde_volumes  WG_TNFS_SAIDA.QTDE_VOLUME%TYPE;
         v_vlr_desp_aces WG_TNFS_SAIDA.VLR_DESP_ACES%TYPE;

      BEGIN
         BEGIN
            --Busca valores setados no FSULMAQ_COM011
            v_placa         := FOCCO3I_GERAL_PARAM.GET_VARIAVEL('FSULMAQ_COM011_PLACA');
            v_marca         := FOCCO3I_GERAL_PARAM.GET_VARIAVEL('FSULMAQ_COM011_MARCA');
            v_vlr_frete     := FOCCO3I_GERAL_PARAM.GET_VARIAVEL('FSULMAQ_COM011_FRETE');
            v_vlr_seguro    := FOCCO3I_GERAL_PARAM.GET_VARIAVEL('FSULMAQ_COM011_SEGURO');
            v_vlr_desp_aces := FOCCO3I_GERAL_PARAM.GET_VARIAVEL('FSULMAQ_COM011_DESP_ACESS');
            v_peso_liq      := FOCCO3I_GERAL_PARAM.GET_VARIAVEL('FSULMAQ_COM011_PESO_LIQ');
            v_peso_brt      := FOCCO3I_GERAL_PARAM.GET_VARIAVEL('FSULMAQ_COM011_PESO_BRT');
            v_qtde_volumes  := FOCCO3I_GERAL_PARAM.GET_VARIAVEL('FSULMAQ_COM011_VOLUMES');
            
            UPDATE wg_tnfs_saida
               SET placa         = NVL(v_placa        , placa        )
                 , marca         = NVL(v_marca        , marca        )
                 , vlr_frete     = NVL(v_vlr_frete    , vlr_frete    )
                 , vlr_seguro    = NVL(v_vlr_seguro   , vlr_seguro   )
                 , vlr_desp_aces = NVL(v_vlr_desp_aces, vlr_desp_aces)
                 , peso_liq      = NVL(v_peso_liq     , peso_liq     )
                 , peso_brt      = NVL(v_peso_brt     , peso_brt     )
                 , qtde_volume   = NVL(v_qtde_volumes , qtde_volume  )
             WHERE id = pi_wgtnfs_id;
         EXCEPTION
            WHEN OTHERS THEN
               po_erro := 'Erro ao atualizar os dados da capa da nota fiscal: '
                          ||DBMS_UTILITY.FORMAT_ERROR_STACK||DBMS_UTILITY.FORMAT_ERROR_BACKTRACE;
         END;
      END F3I_ATUALIZA_DADOS_CAPA;

      --Verifica se todos os itens da carga estão no agrupamento da oportunidade que está sendo faturada
      PROCEDURE F3I_VALIDA_ITENS_CARGA ( pi_wgtnfs_id  IN WG_TNFS_SAIDA.ID%TYPE
                                       , po_erro      OUT VARCHAR2
                                       ) IS

         v_existe  NUMBER;
         v_item    VARCHAR2(100);
         v_carga   VARCHAR2(100);
         v_num_opp WG_FSULMAQ_COM008.NUM_OPP%TYPE;
         v_erro    VARCHAR2(4000);

      BEGIN
         FOR c_ite IN (SELECT *
                         FROM wg_titens_nfs wg
                        WHERE wg.wgtnfs_id = pi_wgtnfs_id
                          AND ind_fatura   = 1
                          AND selecionado  = 1
                      )
         LOOP
            BEGIN
               SELECT 1
                 INTO v_existe
                 FROM wg_fsulmaq_com008
                WHERE tipo           = 'CONSULTA'
                  AND nivel          = 3
                  AND itpdv_id_nvl_3 = c_ite.itpdv_id
                  AND ROWNUM         = 1;
            EXCEPTION
               WHEN NO_DATA_FOUND THEN
                  SELECT 'Item '||cod_item||DECODE(c_ite.tmasc_item_id, NULL, NULL, ' ('||c_ite.tmasc_item_id||')')
                    INTO v_item
                    FROM titens_comercial
                   WHERE id = c_ite.itcm_id;

                  SELECT carga||' do dia '||TO_CHAR(dt_geracao, 'DD/MM/YYYY')
                    INTO v_carga
                    FROM tcargas
                   WHERE id = (SELECT plc_id
                                 FROM titens_plc
                                WHERE id = c_ite.itplc_id);

                  SELECT num_opp
                    INTO v_num_opp
                    FROM wg_fsulmaq_com008
                   WHERE tipo   = 'CONSULTA'
                     AND nivel  = 1
                     AND ROWNUM = 1;

                  IF v_erro IS NULL THEN
                     v_erro := v_item||' da carga '||v_carga||' não está no agrupamento da oportunidade '||v_num_opp||'.';
                  ELSE
                     v_erro := v_erro||CHR(10)||v_item||' da carga '||v_carga||' não está no agrupamento da oportunidade '||v_num_opp||'.';
                  END IF;
            END;
         END LOOP;

         po_erro := v_erro;

      END F3I_VALIDA_ITENS_CARGA;

      --Verifica se todos os itens de venda estão 100% liberados no agrupamento de itens (FSULMAQ_COM008)
      PROCEDURE F3I_VALIDA_PERC_LIB_IT_AGRUP ( pi_wgtnfs_id  IN WG_TNFS_SAIDA.ID%TYPE
                                             , po_erro      OUT VARCHAR2
                                             ) IS

         v_num_opp       WG_FSULMAQ_COM008.NUM_OPP%TYPE;
         v_setor_seq     WG_FSULMAQ_COM008.SETOR_SEQ%TYPE;
         v_cod_item      TITENS_COMERCIAL.COD_ITEM%TYPE;
         v_tmasc_item_id TMASC_ITEM.ID%TYPE;
         v_existe        NUMBER;
         v_erro          VARCHAR2(4000);

      BEGIN
         --Percorre todos os itens de venda
         FOR c_ite IN (SELECT SULMAQ_AGRUPA_ITENS.RETORNA_ITPDV_FAT(itpdv_id) itpdv_id_venda
                         FROM wg_titens_nfs
                        WHERE wgtnfs_id   = pi_wgtnfs_id
                          AND selecionado = 1
                          AND ind_fatura  = 1
                        GROUP BY SULMAQ_AGRUPA_ITENS.RETORNA_ITPDV_FAT(itpdv_id)
                      )
         LOOP
            BEGIN
               SELECT SULMAQ_AGRUPA_ITENS.RETORNA_MNEMONICO ( itcm.itempr_id
                                                            , itpdv.tmasc_item_id
                                                            , 'OPORTUNIDADE'
                                                            )
                    , SULMAQ_AGRUPA_ITENS.RETORNA_MNEMONICO ( itcm.itempr_id
                                                            , itpdv.tmasc_item_id
                                                            , 'SETOR_SEQ'
                                                            )
                    , itcm.cod_item
                    , itpdv.tmasc_item_id
                 INTO v_num_opp
                    , v_setor_seq
                    , v_cod_item
                    , v_tmasc_item_id
                 FROM titens_pdv       itpdv
                    , titens_comercial itcm
                WHERE itpdv.itcm_id  = itcm.id
                  AND itpdv.id       = c_ite.itpdv_id_venda;
            EXCEPTION
               WHEN NO_DATA_FOUND THEN
                  v_erro := 'Erro ao buscar os dados do item de venda! ID da TITENS_PDV: '||c_ite.itpdv_id_venda;
                  EXIT;
            END;
            
            BEGIN
               SELECT 1
                 INTO v_existe
                 FROM sdi_agrupamento_perc_lib
                WHERE num_opp             = v_num_opp
                  AND setor_seq_agrupador = v_setor_seq
                  AND perc_agrup          = 100;
            EXCEPTION
               WHEN NO_DATA_FOUND THEN
                  --Caso o agrupamento não esteja 100%, só permite faturar itens alterados manualmente (canetaço)
                  --Verifica se existe algum item que não é canetaço. Nesse caso não deve permitir o faturamento
                  BEGIN
                     SELECT 1
                       INTO v_existe
                       FROM wg_titens_nfs
                      WHERE wgtnfs_id   = pi_wgtnfs_id
                        AND selecionado = 1
                        AND ind_fatura  = 1
                        AND SULMAQ_AGRUPA_ITENS.RETORNA_ITPDV_FAT(itpdv_id) = c_ite.itpdv_id_venda
                        AND EXISTS (SELECT 1
                                      FROM wg_fsulmaq_com008
                                     WHERE tipo             = 'CONSULTA'
                                       AND nivel            = 3
                                       AND itpdv_id_nvl_3   = wg_titens_nfs.itpdv_id
                                       AND NVL(alterado, 0) = 0)
                        AND ROWNUM      = 1;

                     IF v_tmasc_item_id IS NOT NULL THEN
                        v_erro := 'O item '||v_cod_item||' ('||v_tmasc_item_id||') não está 100% liberado para faturamento. Verifique.';
                     ELSE
                        v_erro := 'O item '||v_cod_item||' não está 100% liberado para faturamento. Verifique.';
                     END IF;

                     EXIT;
                  EXCEPTION
                     WHEN NO_DATA_FOUND THEN
                        NULL;
                  END;
            END;
         END LOOP;

         po_erro := v_erro;

      END F3I_VALIDA_PERC_LIB_IT_AGRUP;

      --Retorna o valor com base na cotação da moeda do pedido de venda expedição
      FUNCTION F3I_RETORNA_VLR_COTACAO ( pi_wgtnfs_id   IN WG_TNFS_SAIDA.ID%TYPE
                                       , pi_vlr_entrada IN NUMBER
                                       , pio_dt_cotacao IN OUT DATE
                                       , pio_moe_id     IN OUT TPEDIDOS_VENDA.MOE_ID%TYPE
                                       ) RETURN NUMBER IS
      
         v_novo_valor NUMBER;
      
      BEGIN
         IF pio_dt_cotacao IS NULL THEN
            --Busca a data da nota de venda
            BEGIN
               SELECT TRUNC(nfs.dt_emis)
                 INTO pio_dt_cotacao
                 FROM tnfs_saida        nfs
                    , titens_nfs        itnfs
                    , ttipos_nf         tpnf
                    , thist_mov_ite_pdv hist
                    , wg_fsulmaq_com008 wg
               WHERE nfs.id            = itnfs.nfs_id
                 AND tpnf.id           = itnfs.tpnf_id
                 AND wg.itpdv_id_nvl_1 = hist.itpdv_id
                 AND hist.itnfs_id     = itnfs.id
                 AND tpnf.receita      = 1
                 AND ROWNUM            = 1;
            EXCEPTION
               WHEN NO_DATA_FOUND THEN 
                  pio_dt_cotacao := TRUNC(SYSDATE);
            END;
         END IF;
         
         IF pio_moe_id IS NULL THEN
            --Busca a moeda do pedido de venda expedição
            BEGIN
               SELECT pdv.moe_id
                 INTO pio_moe_id
                 FROM tpedidos_venda pdv
                    , titens_pdv     itpdv
                    , wg_titens_nfs  wg
                WHERE pdv.id       = itpdv.pdv_id
                  AND itpdv.id     = wg.itpdv_id
                  AND wg.wgtnfs_id = pi_wgtnfs_id
                  AND selecionado  = 1
                  AND ind_fatura   = 1
                  AND ROWNUM       = 1;
            EXCEPTION
               WHEN NO_DATA_FOUND THEN
                  pio_moe_id := NULL;
            END;
         END IF;

         IF pio_moe_id IS NOT NULL THEN
            v_novo_valor := ROUND(FOCCO3I_UTIL.COTACAO(pi_vlr_entrada, pio_moe_id, NULL, pio_dt_cotacao, 8), 2);
         ELSE
            v_novo_valor := pi_vlr_entrada;
         END IF;

         RETURN v_novo_valor;
      END F3I_RETORNA_VLR_COTACAO;

      --Verifica no agrupamento se é o faturamento final do item de venda
      --ou seja, se não vai ficar nenhum item expedição pendente após a emissão desta nota
      FUNCTION F3I_E_FATURAMENTO_FINAL_ITEM ( pi_itpdv_id_venda IN TITENS_PDV.ID%TYPE
                                            , pi_wgtnfs_id      IN WG_TNFS_SAIDA.ID%TYPE
                                            ) RETURN NUMBER IS

         v_final NUMBER;

      BEGIN
         BEGIN
            SELECT 0
              INTO v_final
              FROM wg_fsulmaq_com008 wg
             WHERE wg.itpdv_id_nvl_1 = pi_itpdv_id_venda
               AND wg.tipo           = 'CONSULTA'
               AND wg.nivel          = 3
               AND NVL(wg.qtde_sldo, 0) - NVL((SELECT SUM(qtde)
                                                 FROM wg_titens_nfs
                                                WHERE wgtnfs_id = pi_wgtnfs_id
                                                  AND itpdv_id  = wg.itpdv_id_nvl_3), 0) > 0
               AND ROWNUM            = 1;
         EXCEPTION
            WHEN NO_DATA_FOUND THEN
               v_final := 1;
         END;

         RETURN v_final;
      END F3I_E_FATURAMENTO_FINAL_ITEM;

      --Insere o item de venda na nota fiscal
      PROCEDURE F3I_INSERE_ITEM_VENDA ( pi_itpdv_id_venda IN TITENS_PDV.ID%TYPE
                                      , pi_wgtnfs_id      IN WG_TNFS_SAIDA.ID%TYPE
                                      , pi_wgitnfs_id     IN WG_TITENS_NFS.ID%TYPE --Item expedição
                                      , po_wgitnfs_id    OUT WG_TITENS_NFS.ID%TYPE --Retorna item de venda gerado
                                      ) IS

         wg_itnfs WG_TITENS_NFS%ROWTYPE;
         v_final  NUMBER;

      BEGIN
         SELECT *
           INTO wg_itnfs 
           FROM wg_titens_nfs
          WHERE id = pi_wgitnfs_id;

         v_final := F3I_E_FATURAMENTO_FINAL_ITEM(pi_itpdv_id_venda, pi_wgtnfs_id);

         wg_itnfs.itpdv_id := pi_itpdv_id_venda;
         wg_itnfs.itplc_id := NULL;

         SELECT seq_id_wg_titens_nfs.NEXTVAL
              , ite.cod_item
              , NVL(itpdv.descricao, ite.desc_tecnica)||DECODE(v_final, 1, ' (TOTAL) ', 0, ' (PARCIAL) ')
              , itcm.id
              , itempr.id
              , itpdv.tmasc_item_id
              , itpdv.id
              , (SELECT MAX(num_linha)+1 FROM wg_titens_nfs)
              , itpdv.obs
           INTO wg_itnfs.id
              , wg_itnfs.cod_item
              , wg_itnfs.desc_item
              , wg_itnfs.itcm_id
              , wg_itnfs.itempr_id
              , wg_itnfs.tmasc_item_id
              , wg_itnfs.itpdv_id
              , wg_itnfs.num_linha
              , wg_itnfs.obs
           FROM titens_pdv       itpdv
              , titens_comercial itcm
              , titens_empr      itempr
              , titens           ite
          WHERE itpdv.id       = pi_itpdv_id_venda
            AND itpdv.itcm_id  = itcm.id
            AND itcm.itempr_id = itempr.id
            AND itempr.item_id = ite.id;

         wg_itnfs.vlr_frete          := 0;   wg_itnfs.vlr_desc           := 0;   wg_itnfs.vlr_acres          := 0;
         wg_itnfs.vlr_total          := 0;   wg_itnfs.vlr_seguro         := 0;   wg_itnfs.vlr_total_faturado := 0;
         wg_itnfs.vlr_desp_aces      := 0;   wg_itnfs.vlr_desc_zf        := 0;   wg_itnfs.qtde               := 0;
         wg_itnfs.qtde_corrigida     := 0;   wg_itnfs.base_csll          := 0;   wg_itnfs.base_pis           := 0;
         wg_itnfs.base_cofins        := 0;   wg_itnfs.tpnf_atua_estq     := 'TM'; --Baixa filhos
         wg_itnfs.base_ir            := 0;   wg_itnfs.base_iss           := 0;   wg_itnfs.base_inss          := 0;
         wg_itnfs.vlr_csll           := 0;   wg_itnfs.vlr_pis            := 0;   wg_itnfs.vlr_cofins         := 0;
         wg_itnfs.vlr_ir             := 0;   wg_itnfs.vlr_iss            := 0;   wg_itnfs.vlr_inss           := 0;
         wg_itnfs.base_icms          := 0;   wg_itnfs.base_sub_icms      := 0;   wg_itnfs.base_ipi           := 0;
         wg_itnfs.vlr_icms           := 0;   wg_itnfs.vlr_isen_icms      := 0;   wg_itnfs.vlr_out_icms       := 0;
         wg_itnfs.vlr_sub_icms       := 0;   wg_itnfs.vlr_red_icms       := 0;   wg_itnfs.vlr_ipi            := 0;
         wg_itnfs.vlr_isen_ipi       := 0;   wg_itnfs.vlr_out_ipi        := 0;   wg_itnfs.vlr_red_ipi        := 0;
         wg_itnfs.vlr_icms_acres     := 0;   wg_itnfs.vlr_ret_csll       := 0;   wg_itnfs.vlr_ret_pis        := 0;
         wg_itnfs.vlr_ret_cofins     := 0;   wg_itnfs.vlr_ret_ir         := 0;   wg_itnfs.vlr_ret_iss        := 0;
         wg_itnfs.vlr_ret_inss       := 0;   wg_itnfs.vlr_contabil       := 0;   wg_itnfs.base_comis         := 0;
         wg_itnfs.vlr_liq_item       := 0;   wg_itnfs.vlr_bruto          := 0;   wg_itnfs.vlr_brt            := 0;
         wg_itnfs.base_pis_zf        := 0;   wg_itnfs.vlr_pis_zf         := 0;   wg_itnfs.base_cofins_zf     := 0;
         wg_itnfs.vlr_cofins_zf      := 0;   wg_itnfs.base_ret_csll      := 0;   wg_itnfs.base_ret_pis       := 0;
         wg_itnfs.base_ret_cofins    := 0;   wg_itnfs.base_ret_ir        := 0;   wg_itnfs.base_ret_iss       := 0;
         wg_itnfs.base_ret_inss      := 0;   wg_itnfs.vlr_sub_icm_s_ben  := 0;   wg_itnfs.base_difer_icms    := 0;
         wg_itnfs.vlr_difer_icms     := 0;   wg_itnfs.vlr_icms_dev       := 0;   wg_itnfs.vlr_sub_icms_dev   := 0;
         wg_itnfs.base_ibpt          := 0;   wg_itnfs.vlr_ibpt           := 0;   wg_itnfs.vlr_red_sub_icms   := 0; 
         wg_itnfs.ind_fatura         := 5;   wg_itnfs.vlr_ibpt_est       := 0;

         INSERT INTO wg_titens_nfs VALUES wg_itnfs;
         
         po_wgitnfs_id := wg_itnfs.id;
      END F3I_INSERE_ITEM_VENDA;

      --Procedimento para alterar o tipo de nota conforme cadastro
      PROCEDURE F3I_ALTERA_TPNF_ITENS_NOTA ( pi_wgtnfs_id IN WG_TNFS_SAIDA.ID%TYPE ) IS

         v_tpnf_id       TTIPOS_NF.ID%TYPE;
         v_clas_fisc_id  TCLAS_FISC.ID%TYPE;
         v_itcm_id       TITENS_COMERCIAL.ID%TYPE;
         v_tmasc_item_id TMASC_ITEM.ID%TYPE;

      BEGIN
         --Percorre todos os itens de venda
         FOR c_ite_ven IN (SELECT *
                             FROM wg_titens_nfs
                            WHERE wgtnfs_id   = pi_wgtnfs_id
                              AND ind_fatura  = 1
                              AND selecionado = 1
                            ORDER BY num_linha
                          )
         LOOP
            BEGIN
               SELECT tpnf_id
                    , clas_fisc_id
                    , itcm_id
                    , tmasc_item_id
                 INTO v_tpnf_id
                    , v_clas_fisc_id
                    , v_itcm_id
                    , v_tmasc_item_id
                 FROM titens_pdv
               WHERE id = c_ite_ven.itpdv_id;
            EXCEPTION
               WHEN NO_DATA_FOUND THEN
                  v_tpnf_id       := NULL;
                  v_clas_fisc_id  := NULL;
                  v_itcm_id       := NULL;
                  v_tmasc_item_id := NULL;
            END;

            IF v_clas_fisc_id IS NULL THEN
               BEGIN
                  SELECT itcn_conf.clas_fisc_id
                    INTO v_clas_fisc_id
                    FROM titens_contabil  itcn
                       , titens_ctab_conf itcn_conf
                       , titens_comercial itcm 
                  WHERE itcn_conf.itcn_id       = itcn.id
                    AND itcn.itempr_id          = itcm.itempr_id
                    AND itcm.id                 = v_itcm_id
                    AND itcn_conf.tmasc_item_id = v_tmasc_item_id;
               EXCEPTION
                  WHEN NO_DATA_FOUND THEN
                     BEGIN
                        SELECT itcn.clas_fisc_id
                          INTO v_clas_fisc_id
                          FROM titens_contabil  itcn
                             , titens_comercial itcm
                         WHERE itcn.itempr_id = itcm.itempr_id
                           AND itcm.id        = v_itcm_id;
                     EXCEPTION
                        WHEN NO_DATA_FOUND THEN
                           NULL;
                     END;
               END;
            END IF;

            UPDATE wg_titens_nfs
               SET tpnf_id      = NVL(v_tpnf_id     , tpnf_id)
                 , clas_fisc_id = NVL(v_clas_fisc_id, clas_fisc_id)
             WHERE id = c_ite_ven.id;
         END LOOP;
      END F3I_ALTERA_TPNF_ITENS_NOTA;

      --Procedimento que gera os dados na tabela W_FFAT0200_AGR_ITEM, para posterior atendimento pela COM_FAT_GERA_ITENS_DA_NFS
      PROCEDURE F3I_CONTROLA_ATENDIMENTO_ITENS ( pi_wgtnfs_id IN WG_TNFS_SAIDA.ID%TYPE
                                               , pi_sessao    IN NUMBER
                                               ) IS
      
      BEGIN
         DELETE w_ffat0200_agr_item
          WHERE sessao = pi_sessao;

         --Percorre todos os itens de venda
         FOR c_ite_ven IN (SELECT *
                             FROM wg_titens_nfs
                            WHERE wgtnfs_id   = pi_wgtnfs_id
                              AND ind_fatura  = 1
                              AND selecionado = 1
                            ORDER BY num_linha
                          )
         LOOP
            --Percorre todos os itens expedição do item de venda
            FOR c_ite_exp IN (SELECT *
                                FROM wg_titens_nfs
                               WHERE wgtnfs_id   = pi_wgtnfs_id
                                 AND ind_fatura  = 9
                                 AND SULMAQ_AGRUPA_ITENS.RETORNA_ITPDV_FAT(itpdv_id) = c_ite_ven.itpdv_id
                             )
            LOOP
               INSERT INTO w_ffat0200_agr_item
                         ( sessao
                         , itpdv_id
                         , itpdv_id_pai
                         , qtde
                         , itplc_id
                         )
                  VALUES ( pi_sessao
                         , c_ite_exp.itpdv_id
                         , c_ite_ven.itpdv_id
                         , c_ite_exp.qtde
                         , c_ite_exp.itplc_id
                         );
            END LOOP;

            --Se for o último faturamento para o item de venda então atende o mesmo
            IF F3I_E_FATURAMENTO_FINAL_ITEM(c_ite_ven.itpdv_id, pi_wgtnfs_id) = 1 THEN
               INSERT INTO w_ffat0200_agr_item
                         ( sessao
                         , itpdv_id
                         , itpdv_id_pai
                         , qtde
                         , itplc_id
                         )
                  VALUES ( pi_sessao
                         , c_ite_ven.itpdv_id
                         , c_ite_ven.itpdv_id
                         , c_ite_ven.qtde
                         , NULL
                         );
            END IF;
         END LOOP;
      END F3I_CONTROLA_ATENDIMENTO_ITENS;

      --Procedimento que gera os dados na tabela W_FFAT0200_FILHOS, para posterior baixa de estoque pela COM_FAT_SAIDA_ITENS_FILHOS
      PROCEDURE F3I_CONTROLA_BAIXA_ESTOQUE ( pi_wgtnfs_id IN WG_TNFS_SAIDA.ID%TYPE
                                           , pi_sessao    IN NUMBER
                                           ) IS
      
      BEGIN
         DELETE w_ffat0200_filhos
          WHERE sessao = pi_sessao;

         --Percorre todos os itens de venda
         FOR c_ite_ven IN (SELECT *
                             FROM wg_titens_nfs
                            WHERE wgtnfs_id   = pi_wgtnfs_id
                              AND ind_fatura  = 1
                              AND selecionado = 1
                            ORDER BY num_linha
                          )
         LOOP
            --Percorre todos os itens expedição do item de venda
            FOR c_ite_exp IN (SELECT *
                                FROM wg_titens_nfs
                               WHERE wgtnfs_id   = pi_wgtnfs_id
                                 AND ind_fatura  = 9
                                 AND SULMAQ_AGRUPA_ITENS.RETORNA_ITPDV_FAT(itpdv_id) = c_ite_ven.itpdv_id
                             )
            LOOP
               INSERT INTO w_ffat0200_filhos
                         ( sessao
                         , num_linha
                         , itempr_id
                         , tmasc_item_id
                         , itempr_id_pai
                         , qtde
                         , vlr_unit
                         , almox_id
                         )
                  VALUES ( pi_sessao
                         , c_ite_ven.id
                         , c_ite_exp.itempr_id
                         , c_ite_exp.tmasc_item_id
                         , c_ite_ven.itempr_id
                         , c_ite_exp.qtde
                         , 0
                         , c_ite_exp.almox_id
                         );
            END LOOP;
         END LOOP;
      END F3I_CONTROLA_BAIXA_ESTOQUE;

   BEGIN
      FOCCO3I_PARAMETROS.GET_PARAMETRO('pi_wgnfs_id' , pi_wgtnfs_id);
      FOCCO3I_PARAMETROS.GET_PARAMETRO('pi_sessao'   , pi_sessao   );
      FOCCO3I_PARAMETROS.GET_PARAMETRO('pi_empr_id'  , pi_empr_id  );

      pi_sessao := NVL(pi_sessao, USERENV('SESSIONID'));

      BEGIN
         SELECT origem_fat
           INTO v_origem_fat
           FROM wg_tnfs_saida
         WHERE id = pi_wgtnfs_id;
      EXCEPTION
        WHEN NO_DATA_FOUND THEN 
           v_origem_fat := NULL;
      END;

      --Verifica se o faturamento é por carga (FFAT0220)
      IF NVL(v_origem_fat, 'XYZ') <> 'PLC' THEN
         RAISE e_n_continua;
      END IF;

      --Verifica se é faturamento de Oportunidades (FSULMAQ_COM008) -> Agrupamento de Itens
      v_num_opp := F3I_RETORNA_OPP(pi_wgtnfs_id);

      IF v_num_opp IS NULL THEN
         RAISE e_n_continua;
      END IF;

      --Simula Agrupamento de Itens (FSULMAQ_COM008)
      BEGIN
         SULMAQ_AGRUPA_ITENS.INSERE_WG_FSULMAQ_COM008 ( pi_empr_id
                                                      , v_num_opp
                                                      , NULL
                                                      , 'CONSULTA'
                                                      );
      EXCEPTION
         WHEN OTHERS THEN
            v_erro := 'Erro ao buscar dados da Oportunidade '||v_num_opp||': '||DBMS_UTILITY.FORMAT_ERROR_STACK||DBMS_UTILITY.FORMAT_ERROR_BACKTRACE;
            RAISE e_erro_processo;
      END;

      --Atualiza informações da capa da nota
      F3I_ATUALIZA_DADOS_CAPA ( pi_wgtnfs_id
                              , v_erro
                              );

      IF v_erro IS NOT NULL THEN
         RAISE e_erro_processo;
      END IF;

      --Verifica se todos os itens da carga estão no agrupamento da oportunidade que está sendo faturada
      F3I_VALIDA_ITENS_CARGA ( pi_wgtnfs_id
                             , v_erro
                             );

      IF v_erro IS NOT NULL THEN
         RAISE e_erro_processo;
      END IF;

      --Verifica se todos os itens de venda estão 100% liberados no agrupamento de itens (FSULMAQ_COM008)
      F3I_VALIDA_PERC_LIB_IT_AGRUP ( pi_wgtnfs_id
                                   , v_erro
                                   );

      IF v_erro IS NOT NULL THEN
         RAISE e_erro_processo;
      END IF;

      --Atualiza o valor dos itens Expedição com base no Agrupamento de Itens
      FOR c_ite IN (SELECT id
                         , itpdv_id itpdv_id_exp
                         , SULMAQ_AGRUPA_ITENS.RETORNA_ITPDV_FAT(itpdv_id) itpdv_id_venda
                         , qtde
                      FROM wg_titens_nfs
                     WHERE wgtnfs_id   = pi_wgtnfs_id
                       AND selecionado = 1
                       AND ind_fatura  = 1
                   )
      LOOP
         BEGIN
            SELECT ROUND((vlr_total/qtde)*c_ite.qtde, 2)
              INTO v_vlr_total
              FROM wg_fsulmaq_com008
             WHERE itpdv_id_nvl_1 = c_ite.itpdv_id_venda
               AND itpdv_id_nvl_3 = c_ite.itpdv_id_exp
               AND nivel          = 3
               AND tipo           = 'CONSULTA';
         EXCEPTION
            WHEN NO_DATA_FOUND THEN
               v_erro := 'Erro ao buscar o valor do item expedição na Oportunidade '||v_num_opp||'. ITPDV_ID Venda: '||c_ite.itpdv_id_venda
                         ||' - ITPDV_ID Expedição: '||c_ite.itpdv_id_exp;
               RAISE e_erro_processo;
         END;

         --Tratamento para moeda estrangeira
         v_vlr_total := F3I_RETORNA_VLR_COTACAO ( pi_wgtnfs_id
                                                , v_vlr_total
                                                , v_dt_cotacao
                                                , v_moe_id
                                                );

         UPDATE wg_titens_nfs
            SET preco_unit         = ROUND((v_vlr_total/qtde), 2)
              , vlr_liq_item       = ROUND(v_vlr_total, 2)
              , vlr_liq_item_trib  = ROUND(v_vlr_total, 2)
              , vlr_brt            = ROUND(v_vlr_total, 2)
              , vlr_bruto          = ROUND(v_vlr_total, 2)
              , vlr_total_faturado = ROUND(v_vlr_total, 2)
          WHERE id = c_ite.id;
      END LOOP;

      --Insere os itens de venda na nota
      FOR c_ite IN (SELECT SULMAQ_AGRUPA_ITENS.RETORNA_ITPDV_FAT(itpdv_id) itpdv_id_venda
                         , MIN(id) wgitnfs_id
                      FROM wg_titens_nfs
                     WHERE wgtnfs_id   = pi_wgtnfs_id
                       AND selecionado = 1
                       AND ind_fatura  = 1
                     GROUP BY SULMAQ_AGRUPA_ITENS.RETORNA_ITPDV_FAT(itpdv_id)
                   )
      LOOP
         F3I_INSERE_ITEM_VENDA( c_ite.itpdv_id_venda
                              , pi_wgtnfs_id
                              , c_ite.wgitnfs_id
                              , v_wgitnfs_id
                              );
      END LOOP;

      --Desmarca os itens expedição, pois na nota devem sair apenas os itens de venda
      UPDATE wg_titens_nfs
         SET selecionado = 0
           , ind_fatura  = 9 --Seta para 9 para saber quais itens atender e baixar estoque posteriormente
       WHERE wgtnfs_id   = pi_wgtnfs_id
         AND selecionado = 1
         AND ind_fatura  = 1;

      --Seleciona os itens de venda
      UPDATE wg_titens_nfs
         SET selecionado = 1
           , ind_fatura  = 1
       WHERE wgtnfs_id   = pi_wgtnfs_id
         AND ind_fatura  = 5;

      --Busca o valor de venda do item com base nos valores dos itens expedição
      --Ajusta o número da linha dos itens de venda
      v_num_linha := 0;
      FOR c_ite IN (SELECT *
                      FROM wg_titens_nfs
                     WHERE ind_fatura  = 1
                       AND selecionado = 1
                       AND wgtnfs_id   = pi_wgtnfs_id
                     ORDER BY num_linha
                    )
      LOOP
         v_num_linha := v_num_linha+1;

         BEGIN
            SELECT qtde
              INTO v_qtde_venda
              FROM wg_fsulmaq_com008
             WHERE tipo           = 'CONSULTA'
               AND nivel          = 1
               AND itpdv_id_nvl_1 = c_ite.itpdv_id;
         EXCEPTION
            WHEN NO_DATA_FOUND THEN
               v_erro := 'Não foi possível buscar a quantidade de venda do item '||c_ite.cod_item||' - '||c_ite.desc_item||'.';
               RAISE e_erro_processo;
         END;

         BEGIN
            SELECT ROUND(SUM(vlr_liq_item), 2)
              INTO v_vlr_venda
              FROM wg_titens_nfs
             WHERE wgtnfs_id   = pi_wgtnfs_id
               AND selecionado = 0
               AND ind_fatura  = 9
               AND SULMAQ_AGRUPA_ITENS.RETORNA_ITPDV_FAT(itpdv_id) = c_ite.itpdv_id;
         EXCEPTION
            WHEN NO_DATA_FOUND THEN
               v_erro := 'Não foi possível montar o valor de venda do item '||c_ite.cod_item||' - '||c_ite.desc_item||'.';
               RAISE e_erro_processo;
         END;

         UPDATE wg_titens_nfs
            SET num_linha          = v_num_linha
              , qtde               = v_qtde_venda
              , qtde_corrigida     = v_qtde_venda
              , vlr_liq_item       = v_vlr_venda
              , vlr_brt            = v_vlr_venda
              , vlr_bruto          = v_vlr_venda
              , vlr_total_faturado = v_vlr_venda
              , preco_unit         = ROUND(v_vlr_venda/v_qtde_venda, 2)
          WHERE id = c_ite.id;
      END LOOP;

      --Altera o tipo de nota dos itens
      F3I_ALTERA_TPNF_ITENS_NOTA ( pi_wgtnfs_id
                                 );

      --Calcula o restante dos valores
      COM_FAT_CALC_VAL_ITENS ( pi_empr_id
                             , pi_wgtnfs_id
                             , 'A'
                             , v_erro
                             );

      IF v_erro IS NOT NULL THEN
         RAISE e_erro_processo;
      END IF;

      --Faz o atendimento dos itens dos pedidos FUT e expedição
      F3I_CONTROLA_ATENDIMENTO_ITENS ( pi_wgtnfs_id
                                     , pi_sessao
                                     );

      --Realiza a baixa de estoque dos itens expedição
      F3I_CONTROLA_BAIXA_ESTOQUE ( pi_wgtnfs_id
                                 , pi_sessao
                                 );

   EXCEPTION
      WHEN e_n_continua THEN
         RETURN;
      WHEN e_erro_processo THEN
         FOCCO3I_PARAMETROS.SET_PARAMETRO('po_erro', v_erro);
         RETURN;
      WHEN OTHERS THEN
         FOCCO3I_PARAMETROS.SET_PARAMETRO('po_erro', 'Erro geral: '||DBMS_UTILITY.FORMAT_ERROR_STACK||DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
         RETURN;
   END FATURA_CARGA_OPP;

END;
/