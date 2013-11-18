
var current_data;


function has_user(event) {
    if (!current_data || !event.target) return;

    var id = $(event.target).closest("tr").attr("id").split("_")[1];
    var user;

    $.each(current_data.rows, function(i, item) {
        if (item.id == id) {
            user = item.value;
            user.id = id
            return false;
        }
    });

    if (!user) return false
    return user
}


function new_users_click(event) {
    var user = has_user(event)
    if(!user) {
       console.log("noes, no user!");
       return;
    }
    if (event.target) {
       if(event.target.id == "ok_user") {
           $.post("user_accept", { id: user.id });
           console.log("Godkjent!");
           $(event.target).closest("tr").fadeOut("slow");
        } else if(event.target.id == "deny_user") {
           $.post("user_deny", { id: user.id })
              .done(function() {$(event.target).closest("tr").fadeOut("slow");})
              .fail(function() {$(event.target).closest("tr").addClass("alert");})
        } else if ($(event.target).hasClass("user_transaction")) {
           modal_transactions(user)
        } else if ($(event.target).hasClass("user_edit")){
           modal_edit(user)
        }
        update_status();
    }
}

function modal_edit(user){
   $("#user_modal_edit .edit_id").val(user._id);
   $("#user_modal_edit .edit_name").val(user.name);
   $("#user_modal_edit .edit_email").val(user.email);
   $("#user_modal_edit .edit_account").val(user.account);
   $("#user_modal_edit .edit_200").val(user.paid_200 || 0);
   $("#user_modal_edit .edit_250").val(user.paid_250 || 0);
   $("#user_modal_edit .edit_bot").val(user.bot || 0);
   $("#user_modal_edit .edit_giro").val(user.bot_giro || 0);

   $("#user_modal_edit").modal();
}


function register_button() {
   $(".knapp_pluss").click(function() { $(this).prev().val(parseInt($(this).prev().val())+1) } );
   $(".knapp_minus").click(function() { $(this).next().val(parseInt($(this).next().val())-1) } );
}


function modal_transactions(user){
   var tbody = $("#user_transaction_list");
   tbody.empty();

   $.each(user.transactions, function(i, item) {
         tbody.append('<tr>'+
            '<td>' + item.date + '</td>' +
            '<td>' + item.amount + '</td>' +
            '<td>' + item.melding + '</td>' +
            '<td>' + item.konto + '</td>' +
            '<td>' + item.blankett + '</td>' +
            '<tr>');
         //console.log(item);
         });

   $("#user_modal_transactions").modal();
}

function all_users_click(event) {
    var user = has_user(event);

    if ($(event.target).hasClass("user_edit")) {

        if (!user) {
            console.log("oh noes! could not find user");
            return;
        }

        console.log(user);
        modal_edit(user)

    } else if ($(event.target).hasClass("user_transaction")) {
        modal_transactions(user)

    }
}

function show_all_users(event,search) {
    var req = "users/";
    if(search) { 
       req = req + search
       console.log(req)
    }
    $.get(req, function(data) {
        if (!data || !data.rows) {
            alert("something went wrong");
            return;
        }
        current_data = data;
        $(".main_view").hide();

        $("#all_users_tbody").empty();
        $.each(data.rows, function(i, item) {
            if (!item.value) return;

            var user = item.value;
            var row = '<tr id="user_'+user._id+'">'+
                      '<td>' + user.name + '</td>' +
                      '<td>' + user.email + '</td>' +
                      '<td>' + user.join_date + '</td>' +
                      '<td>' + user.valid_from + '</td>' +
                      '<td>' + user.valid_to + '</td>' +
                      '<td>';
            if (user.note)
                row += '<span class="badge badge-info pull-right"><i class="icon-tag icon-white"></i></span>';
            if (user.indiv) {
                var indiv = parseInt(user.indiv);
                if (indiv < 0)
                    row += '<span class="badge badge-important pull-right">'+indiv+'</span>';
                else
                    row += '<span class="badge badge-success pull-right">'+indiv+'</span>';
            }
            if (user.transactions)
                row += '<span class="badge badge-info user_transaction">'+
                       '<i class="icon-barcode icon-white user_transaction"></i></span> ';

            row += '<span class="badge badge-info user_edit"><i class="icon-edit icon-white user_edit"></i></span>';
            row += '</td></tr>';

            $("#all_users_tbody").append(row);
        });

        $("#all_users").fadeIn('fast');
    }, "json");

    return false;
}


function show_new_users() {
    $.get("newusers", function(data) {
        if (!data || !data.rows) {
            alert("something went wrong");
            return;
        }
        current_data = data;

        $(".main_view").hide();

        $("#new_users_tbody").empty();
        $.each(data.rows, function(i, item) {
            if (!item.value) return;

            var user = item.value;
            $("#new_users_tbody").append('<tr id="user_'+user._id+'">'+
                                         '<td>' + user.name + '</td>'+
                                         '<td>' + user.email + '</td>'+
                                         '<td>' + user.account + '</td>'+
                                         '<td>' + user.join_date + '</td>'+
                                         '<td><a href="#" id="ok_user" class="btn btn-mini btn-primary">'+
                                               '<i class="icon-ok icon-white"></i> Godta</a> '+

                                         ((user.transactions)? ('<span class="badge badge-info user_transaction">'+
                                            '<i class="icon-barcode icon-white user_transaction"></i></span> '):'')+
                                            '<span class="badge badge-info user_edit"><i class="icon-edit icon-white user_edit"></i></span>'+

                                             '<a href="#" id="deny_user" class="btn btn-mini">'+
                                               '<i class="icon-remove"></i> Avslå</a></td>'+
                                         '</tr>');
        });

        $("#new_users").fadeIn('fast');
    }, "json");

    return false;
}

function test() {
   console.log($("#user_modal_edit form"));
}

function commit_edit_user() {
   $.post("/users/", $("#user_modal_edit form").serialize()).success(
      function() { 
         $("#user_modal_edit .btn-primary").addClass("btn-success");
      }).fail(
      function() {
         $("#user_modal_edit .btn-primary").addClass("btn-failure");
      });
}

function update_status() {
    $.get("status", function(data) {
        if(data.newcount){
           $("#count_new").text(data.newcount);
        }
        if(data.allcount){
           $("#count_all").text(data.allcount);
        }
    }, "json");
}

function user_search(event) {
   var search = $("#appendedInputButton").val();
   console.log($("#appendedInputButton").val())
   show_all_users(event,search)
}



$(document).ready(function() {
    $("#nav_users_new").click(show_new_users);
    $("#new_users_tbody").click(new_users_click);

    $("#nav_users_all").click(show_all_users);
    $("#all_users_tbody").click(all_users_click);
    $("#submit_edit_user").click(commit_edit_user);
    $("#user_search").click(user_search)
    //$("#submit_edit_user").click(test);
    register_button();
    update_status();
    show_new_users();
});

