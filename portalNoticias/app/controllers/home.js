function mostraDivDeItens(){

   var tar_id = $v("P400_TAR_ID");
   var canc = $v("P400_EXIBIR_CANCELADOS");
   var pend = $v("P400_EXIBIR_PENDENTES");

   var ajaxRequest = new htmldb_Get(null , $v('pFlowId') , "APPLICATION_PROCESS=TESTA_EXISTE_ITEM_NO_CARRINHO" ,  $v('pFlowStepId'));
   ajaxRequest.add("P400_TAR_ID", tar_id);
   ajaxRequest.add("P400_EXIBIR_CANCELADOS", canc);
   ajaxRequest.add("P400_EXIBIR_PENDENTES", pend);
   var ajaxResult = ajaxRequest.get();

   if(ajaxResult.length > 0){

      if (ajaxResult == 1) {
         $(".cl-div-sem-item").hide();
         $(".cl-div-com-item").show();
      }else{
         $(".cl-div-sem-item").show();
         $(".cl-div-com-item").hide();
      }
   }

}
function chamaTelaProduto(itemId){
    var url = 'f?p=&APP_ID.:310:&SESSION.::NO::P310_ITEM_ID:'+itemId+':';

    chamaPaginaApex(310,'P310_ITEM_ID',itemId);
}


function clickItemIconView(item){

    var url;
    var itemId;
    // busca id da div pai, este id é o id do item clicado.
    itemId = $(item).parent().attr("itemid");

    if (itemId == undefined){
		itemId = $(item).parent().find("#dadosItem").attr("itemid");

    if (itemId != undefined){
        url = 'f?p=&APP_ID.:310:&SESSION.::NO::P310_ITEM_ID:'+itemId+':';
        chamaPaginaApex(310,'P310_ITEM_ID',itemId);
    }
}

function navegaItemProd(itemId) {
    if (itemId != undefined){
        url = 'f?p=&APP_ID.:310:&SESSION.::NO::P310_ITEM_ID:'+itemId+':';
        chamaPaginaApex(310,'P310_ITEM_ID',itemId);
    }
}

function chamaEditarObs(){
    $("#modalOBS #openModal").show();//addClass("cl-show");
    $("#modalOBS #openModalFundo").show();
    var texto =  $v("P600_OBSERVACAO");

    $s("P600_OBS_EDIT",texto);

}

function carregaEventosGridItensCarrrinho(){

    carregaEventoChangeQtdeItem();
    carregaEventoChangeEmpresaItem();
    carregaEventoChangeDescontoItem();
    carregaEventoChangeTipoVendaItem();
    carregaEventoClickDeletarItem();
    carregaEventoClickEditarItem();
}



function carregaEventoChangeTipoVendaItem(){

    $("#itens_carrinho .cl-tipo-venda").change(function(){

        atualizaQtdeItemCarrinho(this);

        replicarTipoVendaItem(this);

    });


}


function carregaEventoChangeQtdeItem(){

    $("#itens_carrinho .cl-qtde").change(function(){

        atualizaQtdeItemCarrinho(this);

    });


}

function carregaEventoChangeEmpresaItem(){
    $("#itens_carrinho .cl-empr-id").change(function(){

        atualizaQtdeItemCarrinho(this);

        replicarEmpresaItem(this);

    });

}

function carregaEventoChangeDescontoItem(){
    $("#itens_carrinho .cl-perc-desc").focusin(function(){

        if ($(this).find("option").size() <= 1){

            populaDescontosNoItem(this.find(".cl-perc-desc"));
        }
    });

    $("#itens_carrinho .cl-perc-desc").change(function(){

        atualizaQtdeItemCarrinho(this);

		replicarDescontos(this);
    });

}


function ebreEditarDesconto(elemento){

    populaDescontosNoItem($(elemento).parent().find(".cl-perc-desc"));

}

function atualizaQtdeItemCarrinho(elemento){
   // elemento =  $(elemento).parent();
    var qtde_digitada =  $(elemento).parent().parent().find(".cl-qtde").val();
	var itcar_id = $(elemento).parent().parent().find(".cl-item-car-id").html().trim();
	var item_id = $(elemento).parent().parent().find(".cl-item-id").html().trim();
	var empr_id = $(elemento).parent().parent().find(".cl-empr-id").val().trim();
	var vlr_brt = $(elemento).parent().parent().find(".cl-vlr-brt").html().trim();
	var perc_desc = $(elemento).parent().parent().find(".cl-perc-desc").val().trim();
	var vlr_liq = $(elemento).parent().parent().find(".cl-vlr-liq").html().trim();
	//var vlr_desc = $(elemento).parent().parent().find(".cl-vlr-desc").html().trim();
    var tipo_venda = $(elemento).parent().parent().find(".cl-tipo-venda").val().trim();
    var canc = $(elemento).parent().parent().find(".cl-qtde-canc").html().trim();


    $s("P400_ITEM_CAR_ID",itcar_id);
	$s("P400_ITEM_ID",item_id);
    $s("P400_EMPR_ID",empr_id);
	$s("P400_PERC_DESC",perc_desc);
    $s("P400_TIPO_VENDA",tipo_venda);

    $s("P400_CONTROLE",1);
	$s("P400_QTDE_DIGITADA",qtde_digitada);


    var ajaxRequest = new htmldb_Get(null , $v('pFlowId') , "APPLICATION_PROCESS=AJAX_ATUALIZA_ITEM_CARRINHO" ,  $v('pFlowStepId'));

    ajaxRequest.add("P400_ITEM_CAR_ID", itcar_id);
    ajaxRequest.add("P400_ITEM_ID", item_id);
    ajaxRequest.add("P400_EMPR_ID", empr_id);
    ajaxRequest.add("P400_PERC_DESC", perc_desc);
    ajaxRequest.add("P400_TIPO_VENDA", tipo_venda);
    ajaxRequest.add("P400_QTDE_DIGITADA", qtde_digitada);
    var ajaxResult = ajaxRequest.get();

    var retorno = "";

    if(ajaxResult.length > 0){

       retorno = ajaxResult;

       var obj = jQuery.parseJSON(retorno);

        if (obj.erro == 1) {

           $(elemento).parent().parent().find(".cl-preco-unit").html(obj.vlr_unit);
           $(elemento).parent().parent().find(".cl-vlr-brt").html(obj.vlr_brt);
           $(elemento).parent().parent().find(".cl-vlr-liq").html(obj.vlr_liq);
           $(elemento).parent().parent().find(".cl-tipo-venda").val(obj.tipo_venda);
           $(elemento).parent().parent().find(".cl-multiplo").html(obj.multiplo_venda);
           $(elemento).parent().parent().find(".cl-qtde").val(parseInt(obj.qtde));
           $(elemento).parent().parent().find(".cl-qtde").title(canc);
		   $(elemento).parent().parent().find(".cl-empr-id").val(parseInt(obj.emprSel));
		   $(elemento).parent().parent().find(".cl-perc-desc").val(parseInt(obj.decontoSel));

           //carregaDescontoItem(obj.descontos,$(elemento).parent().parent());

           msgAlert(1,obj.msg);

        }else{

           $(elemento).parent().parent().find(".cl-preco-unit").html(obj.vlr_unit);
           $(elemento).parent().parent().find(".cl-vlr-brt").html(obj.vlr_brt);
           $(elemento).parent().parent().find(".cl-vlr-liq").html(obj.vlr_liq);
           $(elemento).parent().parent().find(".cl-tipo-venda").val(obj.tipo_venda);
           $(elemento).parent().parent().find(".cl-multiplo").html(obj.multiplo_venda);
           $(elemento).parent().parent().find(".cl-qtde").val(parseInt(obj.qtde));
           //$(elemento).parent().parent().find(".cl-qtde").title(canc);
            $(elemento).parent().parent().find(".cl-qtde").attr('title',canc);

           carregaDescontoItem(obj.descontos,$(elemento).parent().parent(),parseInt(obj.decontoSel));
       }
	}
    atualizaInfoCarrinho();
    $s("P0_CARREGA_INFO_CARRINHO",Math.random());
}

function replicarEmpresaItem(elemento){

	var itcar_id = $(elemento).parent().parent().find(".cl-item-car-id").html().trim();
	$s("P400_ITEM_CAR_ID",itcar_id);
	var ajaxRequest = new htmldb_Get(null , $v('pFlowId') , "APPLICATION_PROCESS=TESTA_REPLICA_EMPRESA" ,  $v('pFlowStepId'));
    ajaxRequest.add("P400_ITEM_CAR_ID", itcar_id);
    var ajaxResult = ajaxRequest.get();

	if(ajaxResult.length > 0){

       if (ajaxResult==1){

            alertify.okBtn("Sim")
            .cancelBtn("Não")
            .confirm("Deseja replicar a mesma empresa para os item abaixo?", function () {

                var ajaxRequest = new htmldb_Get(null , $v('pFlowId') , "APPLICATION_PROCESS=REPLICA_EMPRESA" ,  $v('pFlowStepId'));
				ajaxRequest.add("P400_ITEM_CAR_ID", itcar_id);
				var ajaxResult = ajaxRequest.get();

				if(ajaxResult.length > 0){

                   retorno = ajaxResult;

                   var obj = jQuery.parseJSON(retorno);

                   if (obj.erro == 1){
                       msgAlert(obj.erro,obj.msg);
                   }else{
                       limpaCamposItenNovo();
                       $s("P400_ATUALIZAR_GRIG",1);
                   }
                }

            }, function() {
                // user clicked "cancel"
            });


	   }

	}
}

function replicarTipoVendaItem(elemento){

	var itcar_id = $(elemento).parent().parent().find(".cl-item-car-id").html().trim();
	$s("P400_ITEM_CAR_ID",itcar_id);
	var ajaxRequest = new htmldb_Get(null , $v('pFlowId') , "APPLICATION_PROCESS=TESTA_REPLICA_TIPO_VENDA" ,  $v('pFlowStepId'));
    ajaxRequest.add("P400_ITEM_CAR_ID", itcar_id);
    var ajaxResult = ajaxRequest.get();

	if(ajaxResult.length > 0){

       if (ajaxResult==1){

            alertify.okBtn("Sim")
            .cancelBtn("Não")
            .confirm("Deseja replicar o mesmo tipo de venda para os item abaixo?", function () {

                var ajaxRequest = new htmldb_Get(null , $v('pFlowId') , "APPLICATION_PROCESS=REPLICA_TIPO_VENDA" ,  $v('pFlowStepId'));
				ajaxRequest.add("P400_ITEM_CAR_ID", itcar_id);
				var ajaxResult = ajaxRequest.get();

				if(ajaxResult.length > 0){

                   retorno = ajaxResult;

                   var obj = jQuery.parseJSON(retorno);

                   if (obj.erro == 1){
                       msgAlert(obj.erro,obj.msg);
                   }else{
                       limpaCamposItenNovo();
                       $s("P400_ATUALIZAR_GRIG",1);
                   }
                }

            }, function() {
                // user clicked "cancel"
            });


	   }

	}
}

function replicarDescontos(elemento){

	var itcar_id = $(elemento).parent().parent().find(".cl-item-car-id").html().trim();
	$s("P400_ITEM_CAR_ID",itcar_id);
	var ajaxRequest = new htmldb_Get(null , $v('pFlowId') , "APPLICATION_PROCESS=TESTA_REPLICA_DESCONTO" ,  $v('pFlowStepId'));
    ajaxRequest.add("P400_ITEM_CAR_ID", itcar_id);
    var ajaxResult = ajaxRequest.get();

	if(ajaxResult.length > 0){

       if (ajaxResult==1){

            alertify.okBtn("Sim")
            .cancelBtn("Não")
            .confirm("Deseja replicar o mesmo desconto para os item abaixo?", function () {

                var ajaxRequest = new htmldb_Get(null , $v('pFlowId') , "APPLICATION_PROCESS=REPLICA_DESCONTO" ,  $v('pFlowStepId'));
				ajaxRequest.add("P400_ITEM_CAR_ID", itcar_id);
				var ajaxResult = ajaxRequest.get();

				if(ajaxResult.length > 0){

                   retorno = ajaxResult;

                   var obj = jQuery.parseJSON(retorno);

                   if (obj.erro == 1){
                       msgAlert(obj.erro,obj.msg);
                   }else{
                       limpaCamposItenNovo();
                       $s("P400_ATUALIZAR_GRIG",1);
                   }
                }

            }, function() {
                // user clicked "cancel"
            });


	   }

	}
}

function carregaListaDescontos(){

	var arrayRows = $('#itens_carrinho tbody tr').find(".cl-list-perc-desc").parent().parent();

	$.each(arrayRows, function( index, value ) {

		populaDescontosNoItem($(value).find(".cl-perc-desc"));
    });

}

function populaDescontosNoItem(elemento){

	var itcar_id = $(elemento).parent().parent().parent().find(".cl-item-car-id").html().trim();
    var descSelected = $(elemento).parent().parent().find("#PERC_DESC_ID").html().trim();
    var cli_id = $v("P400_CLI_ID");


    $s("P400_ITEM_CAR_ID",itcar_id);
	$s("P400_CLI_ID",cli_id);

    var ajaxRequest = new htmldb_Get(null , $v('pFlowId') , "APPLICATION_PROCESS=AJAX_CARREGA_DESCONTOS_ITEM" ,  $v('pFlowStepId'));
    ajaxRequest.add("P400_ITEM_CAR_ID", itcar_id);
    ajaxRequest.add("P400_CLI_ID", cli_id);
    var ajaxResult = ajaxRequest.get();

    var retorno = "";

    if(ajaxResult.length > 0){

       retorno = ajaxResult;

       var obj = jQuery.parseJSON(retorno);

        if (obj.erro == 0) {
           carregaDescontoItem(obj.descontos,$(elemento).parent().parent(),descSelected);
        }
	}

}

function carregaDescontoItem(jsonObj,elemento,descSelected){

   var eSelect = $(elemento).find(".cl-perc-desc");
  // var descSelected = $(elemento).find("#PERC_DESC_ID").html().trim();

   if (!isEmpty(descSelected)){

       $(eSelect).empty();
       $.each(jsonObj, function( index, value ) {
         $(eSelect).append(
           $('<option>'
             , { value: value.perc
               , text: value.desc
               })
         );
       });

      $(eSelect).find('option[value='+descSelected+']').attr('selected','selected');
   }
}

function carregaEventoClickDeletarItem(){

    $("#itens_carrinho .fa-trash").parent().click(function(){
        var itcar_id = this.parent().parent().find(".cl-item-car-id").html().trim();
        $s("P400_ITEM_CAR_ID",itcar_id);

        var ajaxRequest = new htmldb_Get(null , $v('pFlowId') , "APPLICATION_PROCESS=DETELA_ITEM_CARRINHO" ,  $v('pFlowStepId'));
        ajaxRequest.add("P400_ITEM_CAR_ID", itcar_id);
        var ajaxResult = ajaxRequest.get();

       if(ajaxResult.length > 0){

           retorno = ajaxResult;

           var obj = jQuery.parseJSON(retorno);
           if (obj.erro == 0) {
               $s("P400_ATUALIZAR_GRIG",1);
               atualizaInfoCarrinho();
           }else{
              msgAlert(1,obj.msg);
           }
		}
    });


}

function carregaEventoClickEditarItem(){

    $("#itens_carrinho .fa-pencil").parent().click(function(){
        var itpdv_id = this.parent().parent().find(".cl-itpdv-id").html().trim();
        abreManutencaoItem(itpdv_id);

    });
}

function sleep(milliseconds) {
  var start = new Date().getTime();
  for (var i = 0; i < 1e7; i++) {
    if ((new Date().getTime() - start) > milliseconds){
      break;
    }
  }
}

function gerarPedidos(){
  var elements = $("#itens_carrinho  tbody input[name='f01']:checked:enabled").parent().parent().find(".cl-num-item");
	var itensSelecionados = "";

	$.each(elements, function( key, value ) {
		if (itensSelecionados == "" ) {
			itensSelecionados = $(value).text();
		}else{
			itensSelecionados += "," + $(value).text();
		}
	});

	var car_id = $v("P400_CAR_ID");
    var semComis = $v("P400_GERA_SEM_COMIS");
    $s("P400_CAR_ID",car_id);
    $s("F400_ITENS_CAR_SELECTED",itensSelecionados);


	var ajaxRequest2 = new htmldb_Get(null , $v('pFlowId') , "APPLICATION_PROCESS=AJAX_GERA_PEDIDOS" ,  $v('pFlowStepId'));
	ajaxRequest2.add("P400_CAR_ID", car_id);
	ajaxRequest2.add("F400_ITENS_CAR_SELECTED", itensSelecionados);
    ajaxRequest2.add("P400_GERA_SEM_COMIS", semComis);
	var ajaxResult2 = ajaxRequest2.get();

	var retorno = "";
	hideLoader();
	if(ajaxResult2.length > 0){
      retorno = ajaxResult2;
      var obj = jQuery.parseJSON(retorno);

      alertify.alert(obj.msg, function () {
          if (obj.erro == 0) {
              $s("P400_ATUALIZAR_GRIG",0);
              $s("P400_GERA_SEM_COMIS",0);
          }


      });

      /*//msgAlert(obj.erro,obj.msg);
        $("#modalAlert_id #btnAlertOk").click(function(){
          $s("P400_ATUALIZAR_GRIG",0);
      });
      */
    }
}

function clickGerarPedido(){

    showLoader();

    setTimeout(gerarPedidos, 100);

}

function clickAddItem(){

	var ajaxRequest = new htmldb_Get(null , $v('pFlowId') , "APPLICATION_PROCESS=AJAX_ADD_ITEM_CARRINHO" ,  $v('pFlowStepId'));
	ajaxRequest.add("P400_ITEMPR_ID_NOVO", $v("P400_ITEMPR_ID_NOVO"));
	ajaxRequest.add("P400_TAR_ID",  $v("P400_TAR_ID"));
    ajaxRequest.add("P400_PRECO_UNIT_ITEM_NOVO",  $v("P400_PRECO_UNIT_ITEM_NOVO"));
    ajaxRequest.add("P400_QTDE_ITEM_NOVO",  $v("P400_QTDE_ITEM_NOVO"));
    ajaxRequest.add("P400_TPRVEN_IT_IDS_ITEM_NOVO",  $v("P400_TPRVEN_IT_IDS_ITEM_NOVO"));
    ajaxRequest.add("P400_PERC_ITEM_NOVO",  $v("P400_PERC_ITEM_NOVO"));



	var ajaxResult = ajaxRequest.get();

	var retorno = "";

	if(ajaxResult.length > 0){

	   retorno = ajaxResult;

	   var obj = jQuery.parseJSON(retorno);

	   if (obj.erro == 1){
	       msgAlert(obj.erro,obj.msg);
	   }else{
           $s("P400_CAR_ID",obj.car_id);
           limpaCamposItenNovo();
           $s("P400_ATUALIZAR_GRIG",1);
           mostraDivDeItens();
           $("#P400_COD_ITEM_NOVO").focus();
       }
	}
    $s("P0_CARREGA_INFO_CARRINHO",Math.random());
}

function clickLimpaCarrinho(){

    alertify.okBtn("Sim")
        .cancelBtn("Não")
        .confirm("Deseja mesmo limpar esse carrinho?", function () {

        var ajaxRequest = new htmldb_Get(null , $v('pFlowId') , "APPLICATION_PROCESS=AJAX_LIMPA_CARRINHO" ,  $v('pFlowStepId'));
        ajaxRequest.add("P400_CAR_ID", $v("P400_CAR_ID"));

        var ajaxResult = ajaxRequest.get();

        var retorno = "";

        if(ajaxResult.length > 0){

           retorno = ajaxResult;

           var obj = jQuery.parseJSON(retorno);

           if (obj.erro == 1){
               msgAlert(obj.erro,obj.msg);
           }else{
               limpaCamposItenNovo();
           }
        }

        mostraDivDeItens();

        $s("P0_CARREGA_INFO_CARRINHO",Math.random());
        $s("P400_ATUALIZAR_GRIG",Math.random());

    }, function() {
                // user clicked "cancel"
    });

    $s("P0_CARREGA_INFO_CARRINHO",Math.random());


}

function limpaCamposItenNovo(){

    $s("P400_COD_ITEM_NOVO",null);
    $s("P400_DESCRICAO_ITEM_NOVO",null);
    $s("P400_QTDE_ITEM_NOVO",null);
    $s("P400_PRECO_UNIT_ITEM_NOVO",null);
    $s("P400_VALOR_TOTAL_ITEM_NOVO",null);
    $s("P400_ITEMPR_ID_NOVO",null);

}

function chamaTelaAtendimento(){
     var url = 'f?p=&APP_ID.:250:&SESSION.::::::';
     chamaPaginaApex(1,null,null);

}

function abreManutencaoItem(piItpdvId){
    if (piItpdvId > 0){
        chamaPaginaApex(520,'P520_ITPDV_ID',piItpdvId);
    }
}

function chamaTelaPedido(pdvId){
   if (pdvId > 0){
        chamaPaginaApex(500,'P500_PDV_ID',pdvId);
   }
}

function carregaHoverlements(){

    hintElemet($("#btn_obs_cli"),$("#P400_OBS_CLI"));
    hintElemet($("#btn_sucata"),$("#P400_CREDITO_SUCATA"));
    hintElemet($("#btn_garantia"),$("#P400_CREDITO_GARANTIA"));
    hintElemet($("#btn_credito_devolucao"),$("#P400_CREDITO_DEVOLUCAO"));
    hintElemet($("#btn_limite_credito"),$("#P400_LIMITE_CREDITO"));

}

function hintElemet(elementPos,elementText){

    $(elementPos).attr('title', $(elementText).val());

}

function balloonElemet(elementPos,elementText){

    //$(elementPos).prop('tooltipText', elementText).val());
    $(elementPos).attr('title', $(elementText).val());

    $(elementPos).hover(function(){
		$("#ballon").show();

        $(window).mousemove( function(e){

            topCalc  = $(elementPos).offset().top - window.scrollY+45;
            leftCalc = $(elementPos).offset().left - window.scrollX-15;
            $("#ballon .row").html($(elementText).val());
            $('#ballon').css({
			   left:  leftCalc,
			   top:   topCalc
			});

		});

	},
	function(){
		$("#ballon").hide();
	});

}

function isEmpty(value){

    if (value == null || value == undefined || value ==""){
         return true;
    }else{
        return false;
    }

}

function chamaTelaMotivosBloqueio(){

   var car_id = $v("P400_CAR_ID");

   var ajaxRequest = new htmldb_Get(null , $v('pFlowId') , "APPLICATION_PROCESS=TESTA_CARRINHO_COM_PDV_GERADO" ,  $v('pFlowStepId'));
   ajaxRequest.add("P400_CAR_ID", car_id);
   var ajaxResult = ajaxRequest.get();

   if(ajaxResult.length > 0){

      if (ajaxResult == 1) {

          $("#modal_motivos_bloqueio #openModal").addClass('cl-dialog-verificar');
          $("#modal_motivos_bloqueio #openModal").show();

      }else{
         msgAlert(0,"Não existe pedido gerado para ser verificado.");
      }
   }

}

function chamaTelaImportacao(){
     P0_SEQ_SESSAO
     var url = 'f?p=&APP_ID.:410:&SESSION.:::::P0_SEQ_SESSAO:';
     chamaPaginaApex(410,null,null);

}

function vaiParaHomeDoUsuario(){
	var pagina_id = $v("P0_PAGINA_HOME_ID");
	if (pagina_id.length > 0 ){
		var seq_sessao = getValueParUrl("P0_SEQ_SESSAO");
        $s("P0_SEQ_SESSAO",seq_sessao);
        var url = 'f?p=&APP_ID.:1:&SESSION.:::::P0_SEQ_SESSAO:'+seq_sessao;
        chamaPaginaApex(pagina_id,null,null);
	}
}

function finalizarTarefa(){

   alertify.okBtn("Sim")
        .cancelBtn("Não")
        .confirm("Deseja finalizar esta tarefa?", function () {
       var tar_id = $v("P400_TAR_ID");
       var ajaxRequest = new htmldb_Get(null , $v('pFlowId') , "APPLICATION_PROCESS=AJAX_FINALIZA_TAREFA" ,  $v('pFlowStepId'));
       ajaxRequest.add("P400_TAR_ID", tar_id);
	   var ajaxResult = ajaxRequest.get();

	   if(ajaxResult.length > 0){

          var obj = jQuery.parseJSON(ajaxResult);

          if (obj.erro == 1){
              msgAlert(obj.erro,obj.msg);
          }else{

              if ($v('P400_TAR_ID') ==  $v('P400_TAR_ID')) {
                  $s('P400_TAR_ID',null);
              }
              chamaTelaAtendimento();
              atualizaInfoCarrinho();
          }
       }

   }, function() {
       // user clicked "cancel"
   });

}

function chamaEditarObs(){
    $("#modalOBS #openModal").show();
    $("#modalOBS #openModalFundo").show();
    var texto =  $v("P400_OBSERVACAO");
    $s("P400_OBS_EDIT",texto);
}

function getUrlParameter(sParam) {
    var sPageURL = decodeURIComponent(window.location.search.substring(1)),
        sURLVariables = sPageURL.split('&'),
        sParameterName,
        i;

    for (i = 0; i < sURLVariables.length; i++) {
        sParameterName = sURLVariables[i].split('=');

        if (sParameterName[0] === sParam) {
            return sParameterName[1] === undefined ? true : sParameterName[1];
        }
    }
};

function getValueParUrl(parameterName){

  var retorno = "";

  var value = getUrlParameter("p");
  if (value.length > 0){
      var parametros = value.split(":");

      if (parametros.length > 0){
          var parametrosNames = parametros[6].split(",");
          var parametrosVelues = parametros[7].split(",");

          if (parametrosNames.length > 0 && parametrosNames.length == parametrosVelues.length){

              $(parametrosNames).each(function( index ) {

                if (parametrosNames[index] == parameterName){
                  retorno = parametrosVelues[index];
                  return;
                }
              });

          }
      }
  }

  return retorno;

}

function abrePopupPromo(){
    var msg = $v("P400_PROMOCAO_ITEM_NOVO");
    if (msg != null && msg.length > 5){
        $("#popup_promocionais_id #openModal .t-Region-body").html(msg);
        $("#popup_promocionais_id #openModal").addClass("cl-show-promo-postion-auto");
        $("#popup_promocionais_id #openModal").css({"width":"auto;","height":"20px;"});
        $("#popup_promocionais_id #openModal").show();

        $(window).on('mousemove', function(e){
			$('#popup_promocionais_id #openModal').css({
			   left:  e.clientX ,
			   top:   e.clientY
			});
		});
    }
}

function fechaPopupPromo() {
    $("#popup_promocionais_id #openModal").removeClass("cl-show-promo-postion-auto");
    $("#popup_promocionais_id #openModal").hide();
}

function abreHistDescontos(elemento,item_id,empr_id,cli_id){

    //var elemento = $(elemento);

    $s("P400_EMPR_ID_AUX", empr_id);
    $s("P400_ITEM_ID_AUX", item_id);
    $s("P400_CLI_ID_AUX", cli_id);

    var ajaxRequest = new htmldb_Get(null , $v('pFlowId') , "APPLICATION_PROCESS=AJAX_RETORNA_HIST_DESC_CLI" ,  $v('pFlowStepId'));
    ajaxRequest.add("P400_EMPR_ID_AUX", empr_id);
    ajaxRequest.add("P400_ITEM_ID_AUX", item_id);
    ajaxRequest.add("P400_CLI_ID_AUX", cli_id);
	var ajaxResult = ajaxRequest.get();

	if(ajaxResult.length > 0){

        var msg = ajaxResult;
        if (msg != null && msg.length > 5){
            $("#popup_hist_desc_id #openModal .t-Region-body").html(msg);
            $("#popup_hist_desc_id #openModal").addClass("cl-show-promo-postion-auto");
            $("#popup_hist_desc_id #openModal").css({"width":"auto;","height":"20px;","border-radius":"0px;"});
            $("#popup_hist_desc_id #openModal").show();

            var left  = $(elemento)[0].getBoundingClientRect().left;
            var top  = $(elemento)[0].getBoundingClientRect().top;

            if (($(elemento)[0].getBoundingClientRect().left + 260) > $( window ).width()) {

                left =  $(elemento)[0].getBoundingClientRect().left - 260;
            }

            if (($(elemento)[0].getBoundingClientRect().top + 260) > $( window ).height()) {

                top =  $(elemento)[0].getBoundingClientRect().top - 260;
            }

            $('#popup_hist_desc_id #openModal').css({
                left: left ,
                top:  top,
                "border-radius":"0px;"
            });

        }

    }


}

function fechaHistDescontos() {
    $("#popup_hist_desc_id #openModal").removeClass("cl-show-promo-postion-auto");
    $("#popup_hist_desc_id #openModal").hide();
}
