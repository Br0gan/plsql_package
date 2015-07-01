CREATE OR REPLACE PACKAGE PACKAGE_API AS

  /* Corey Lee's custom procedures and functions */
module_  CONSTANT VARCHAR2(25) := 'ORDER';
lu_name_ CONSTANT VARCHAR2(25) := 'CustomerOrderFlow';

PROCEDURE Coreys_Release;

PROCEDURE Pop_Delivery_Details(order_no_ in varchar2);

FUNCTION Get_Delivery_Key(invoice_no_ IN VARCHAR2) RETURN VARCHAR2;

FUNCTION Get_Sender_Id(Message_Id_ IN NUMBER) RETURN VARCHAR2;

PROCEDURE Enter_Freight_Line(delivery_key_ IN VARCHAR2,
                              tracking_number_ IN VARCHAR2,
                              charge_ IN NUMBER,
                              weight_ IN NUMBER,
                              package_qty_ IN NUMBER,
                              status_ in NUMBER);


FUNCTION Find_Value(string_ in varchar2, delimiter_ in varchar2, iteration_ in number) RETURN VARCHAR2;

FUNCTION Get_Site_From_Inv(invoice_no_ in VARCHAR2) RETURN VARCHAR2;

FUNCTION CheckIT_Dummy(delivery_key_ IN VARCHAR2) RETURN VARCHAR2;

FUNCTION Get_Invo_Stat_Sum(customer_no_ IN VARCHAR2, start_ IN VARCHAR2, end_ IN VARCHAR2) RETURN NUMBER;

END COREYS_PACKAGE_API;
/


CREATE OR REPLACE PACKAGE BODY COREYS_PACKAGE_API AS
FUNCTION Get_Site_From_Inv(invoice_no_ in VARCHAR2) RETURN VARCHAR2
IS

temp_ VARCHAR2(15) := '';

  cursor site_ is
  select contract
  from customer_order_inv_head_uiv
  where invoice_no = invoice_no_;

BEGIN

  open site_;
  fetch site_ into temp_;
  close site_;

  return temp_;
END Get_Site_From_Inv;

PROCEDURE Coreys_Release AS
  --Select all available internal orders for release.
  CURSOR n_orders IS
  select order_no
  from customer_order_tab
  where order_no like 'N%'
  and rowstate = 'Planned'
  and contract <> 'CRSTK';

  BEGIN
    --Loop through orders for release
    for orders in n_orders loop
      customer_order_flow_api.process_from_release_order(orders.order_no);
    end loop;
  END Coreys_Release;

FUNCTION Get_Sender_Id(Message_Id_ IN NUMBER) RETURN VARCHAR2
IS
temp_ VARCHAR2(200) := '';
    CURSOR customer is
    Select sender_id
    from in_message_tab
    where Message_Id_ = message_id;
BEGIN
      OPEN customer;
      FETCH customer INTO temp_;
      CLOSE customer;
  RETURN temp_;
END Get_Sender_Id;

FUNCTION Get_Delivery_Key(invoice_no_ in VARCHAR2) RETURN VARCHAR2
IS

temp_ VARCHAR(15) := '';
site_ VARCHAR(5) := '';

  cursor delivery_key IS
  select unique d.delnote_no
  from customer_order_delivery d, cust_delivery_inv_ref r
  inner join invoice i
  on i.invoice_id = r.invoice_id
  where r.deliv_no = d.deliv_no
  and i.invoice_no = invoice_no_;

  cursor delivery_key_cust IS
  select unique d.delivery_note_ref
  from customer_order_delivery d, cust_delivery_inv_ref r
  inner join invoice i
  on i.invoice_id = r.invoice_id
  where r.deliv_no = d.deliv_no
  and i.invoice_no = invoice_no_;

BEGIN
  site_ := get_site_from_inv(invoice_no_);
  if site_ = 'CUST' then
    open delivery_key_cust;
    fetch delivery_key_cust into temp_;
    close delivery_key_cust;
  else
    open delivery_key;
    fetch delivery_key into temp_;
    close delivery_key;
  end if;
  return temp_;
END Get_Delivery_Key;

PROCEDURE Pop_Delivery_Details(order_no_ in varchar2)
IS
  cursor get_delivery_keys is
  select delnote_no
  from customer_order_deliv_note
  where order_no = order_no_;
BEGIN
  for delivery_keys in get_delivery_keys loop
    ps_delivery_detail_api.create_new_delivery(delivery_keys.delnote_no, order_no_);
  end loop;
  commit;
END Pop_Delivery_Details;

/***********************************************************************************
/Function used to get specific values out of delimiated strings
/Where string_ is the string you want to pull the values from,
/delimeter is the charaecter used to spereate the values
/iteration is which value you want to pull ex. 2 would return 'this' (why|this|value)
***************************************************************************************/

FUNCTION Find_Value(string_ in varchar2, delimiter_ in varchar2, iteration_ in number) RETURN VARCHAR2
IS
  new_string_       varchar2(2000) := '';
	find_string_end   varchar2(500)  := '';     -- End position of value
	find_string_start varchar2(500)  := '';     -- Start posistion of value
	wanted_value      varchar2(500)  := '';     -- Returned value
  info              varchar2(100)  := '';     -- For debuging
	
	BEGIN
  --Logic to use is you are pulling the first interation value
    if(string_ = '') then
       return 'NA';
    end if;

    if (instr(string_, delimiter_, 1, 1) = 0) then
      if (iteration_ > 1) then
        return 'NA';
      else
        return string_;
      end if;
    else
      new_string_ := string_;
    end if;

	 if (iteration_ = 1) then
       find_string_end := instr(new_string_, delimiter_, 1, iteration_) - 1;  
	    wanted_value := substr(new_string_,1, find_string_end);
       if (length(wanted_value) < 1) then 
          wanted_value := NULL;
       end if;
    else
      --logic to use when you are asking for the interation last value.
      find_string_end := instr(new_string_, delimiter_, 1, iteration_);
      if (find_string_end = 0) then
        find_string_start := instr(new_string_, delimiter_, -1, 1) + 1;
        wanted_value := substr(new_string_,find_string_start, length(new_string_) - find_string_start + 1);
        end if;
      if (instr(new_string_, delimiter_, 1, iteration_ - 1) = 0) then 
        return 'NA';
      end if;

      --logic to use for all other iteration values
      if (find_string_end <> 0) then
        find_string_start := instr(new_string_, delimiter_, 1, iteration_ -1) + 1;
        wanted_value := substr(new_string_,find_string_start, find_string_end - find_string_start); 
        end if;
    end if;
    return wanted_value;
END Find_Value;

PROCEDURE Enter_Freight_Line(delivery_key_ IN VARCHAR2,
                              tracking_number_ IN VARCHAR2,
                              charge_ IN NUMBER,
                              weight_ IN NUMBER,
                              package_qty_ IN NUMBER,
                              status_ IN NUMBER)
IS
order_no_ VARCHAR2(20) := '';
today_ DATE := to_date(sysdate, 'DD-MON-YY');

  cursor res is
  select order_no
  from customer_order_deliv_note
  where delnote_no = delivery_key_;

BEGIN

  open res;
  fetch res into order_no_;
  close res;

if (status_ = 0) then
  insert into ps_freight_details_tab
  (delivery_key,order_no,tracking_number,line_package_charge,line_weight,
  pick_up_date,rowversion,package_qty)
  values
  (delivery_key_,order_no_,tracking_number_,charge_,weight_,today_,today_,package_qty_);
  if (coreys_package_api.checkit_dummy(delivery_key_) = 'FALSE') then
    ps_delivery_detail_api.create_new_delivery(delivery_key_, order_no_);
  end if;
end if;

if (status_ = 1) then
  update ps_freight_details_tab
  set tracking_number = tracking_number_,
  line_package_charge = charge_,
  line_weight = weight_,
  package_qty = package_qty_
  where delivery_key = delivery_key_;
end if;

if (status_ = 2) then
  delete from ps_freight_details_tab
  where delivery_key = delivery_key_
  and tracking_number = tracking_number_
  and line_package_charge = charge_
  and line_weight = weight_
  and package_qty = package_qty_;
end if;

commit;

END Enter_Freight_Line;

FUNCTION CheckIT_Dummy(delivery_key_ IN VARCHAR2) RETURN VARCHAR2
IS

  temp_ NUMBER := 0;

  cursor checker is
  select count(delivery_key)
  from ps_delivery_detail_tab
  where delivery_key = delivery_key_;

BEGIN
  open checker;
  fetch checker into temp_;
  close checker;

  if(temp_ <> 0) then
    RETURN 'TRUE';
  else
    RETURN 'FALSE';
  end if;
END CheckIT_Dummy;


FUNCTION Get_Invo_Stat_Sum(statistic_no_ IN VARCHAR2, start_ IN VARCHAR2, end_ IN VARCHAR2) RETURN NUMBER
IS
   cursor my_sum is
      select sum(net_curr_amount) net_ammount
      from cust_ord_invo_stat
      where statistic_no = statistic_no_
      and invoice_date between to_date(start_, 'mm/dd/yy') and to_date(end_, 'mm/dd/yy');
BEGIN
   for total in my_sum loop
      return total.net_ammount;
   end loop;
END Get_Invo_Stat_Sum;

END COREYS_PACKAGE_API;
/
