library ieee;

use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity axis_lago_trigger is
  generic (
  AXIS_TDATA_WIDTH      : natural  := 32;
  -- clock frequency, it is necessary because we use it to calculate
  -- the false pps signal time
  CLK_FREQ              : natural  := 125000000;
  -- data arrays bit numbers
  ADC_DATA_WIDTH        : natural := 14;    
  DATA_ARRAY_LENGTH     : natural := 12;
  METADATA_ARRAY_LENGTH : natural := 10;
  SUBTRIG_ARRAY_LENGTH  : natural := 3
);
port (
  -- System signals
  aclk               : in std_logic;
  aresetn            : in std_logic;

  trig_lvl_i         : in std_logic_vector(AXIS_TDATA_WIDTH-1 downto 0);
  subtrig_lvl_i      : in std_logic_vector(AXIS_TDATA_WIDTH-1 downto 0);
  pps_i              : in   std_logic;
  gpsen_i            : in   std_logic;
  false_pps_led_o    : out  std_logic;

--  pwr_enA            : out  std_logic;
--  data_out           : out  std_logic_vector(2**W-1 downto 0);
--  pfifo_status       : in   std_logic_vector(2 downto 0);
--  ptemperatura       : in   std_logic_vector(15 downto 0);
--  ppresion           : in   std_logic_vector(15 downto 0);
--  phora              : in   std_logic_vector(7 downto 0);
--  pminutos           : in   std_logic_vector(7 downto 0);
--  psegundos          : in   std_logic_vector(7 downto 0);
--  latitude1_port     : in   std_logic_vector(7 downto 0);
--  latitude2_port     : in   std_logic_vector(7 downto 0);
--  latitude3_port     : in   std_logic_vector(7 downto 0);
--  latitude4_port     : in   std_logic_vector(7 downto 0);
--  longitude1_port    : in   std_logic_vector(7 downto 0);
--  longitude2_port    : in   std_logic_vector(7 downto 0);
--  longitude3_port    : in   std_logic_vector(7 downto 0);
--  longitude4_port    : in   std_logic_vector(7 downto 0);
--  ellipsoid1_port    : in   std_logic_vector(7 downto 0);
--  ellipsoid2_port    : in   std_logic_vector(7 downto 0);
--  ellipsoid3_port    : in   std_logic_vector(7 downto 0);
--  ellipsoid4_port    : in   std_logic_vector(7 downto 0);
--  num_vis_sat_port   : in   std_logic_vector(7 downto 0);
--  num_track_sat_port : in   std_logic_vector(7 downto 0);
--  rsf_port           : in   std_logic_vector(7 downto 0)

  -- Slave side
  s_axis_tready     : out std_logic;
  s_axis_tdata      : in std_logic_vector(AXIS_TDATA_WIDTH-1 downto 0);
  s_axis_tvalid     : in std_logic;

  -- Master side
  m_axis_tready     : in std_logic;
  m_axis_tdata      : out std_logic_vector(AXIS_TDATA_WIDTH-1 downto 0);
  m_axis_tvalid     : out std_logic
);
end axis_lago_trigger;

architecture rtl of axis_lago_trigger is

  constant PADDING_WIDTH : natural := AXIS_TDATA_WIDTH/2 - ADC_DATA_WIDTH;

  --ADC related signals
  type  adc_data_array_t is array (DATA_ARRAY_LENGTH-1 downto 0) 
  of std_logic_vector(AXIS_TDATA_WIDTH/2-1 downto 0);
  signal adc_dat_a_reg, adc_dat_a_next : adc_data_array_t;
  signal adc_dat_b_reg, adc_dat_b_next : adc_data_array_t;

  type array_pps_t is array (METADATA_ARRAY_LENGTH-1 downto 0) 
  of std_logic_vector(AXIS_TDATA_WIDTH-1 downto 0);
  signal array_pps_reg, array_pps_next : array_pps_t;

  type array_scalers_t is array (SUBTRIG_ARRAY_LENGTH-1 downto 0) 
  of std_logic_vector(AXIS_TDATA_WIDTH-1 downto 0);
  signal array_scalers_reg, array_scalers_next : array_scalers_t;


  --PPS related signals
  -- clock counter in a second
  signal one_sec_cnt: std_logic_vector(AXIS_TDATA_WIDTH-1 downto 0);      
  -- counter for clock pulses between PPS, it goes to zero at every PPS pulse 
  signal clk_cnt_pps : std_logic_vector(AXIS_TDATA_WIDTH-1 downto 0); 
  signal pps, false_pps : std_logic;

  type pps_st_t is (ZERO, EDGE, ONE);
  signal pps_st_reg, pps_st_next: pps_st_t;
  signal one_clk_pps : std_logic;

  --Trigger related signals
  --Triggers
  signal tr1_s, tr2_s, tr_s              : std_logic; 
  --Sub-Triggers
  signal subtr1_s, subtr2_s, subtr_s     : std_logic; 

  signal tr_status_reg, tr_status_next   : std_logic_vector(AXIS_TDATA_WIDTH-1 downto 0);
  signal cnt_status_reg, cnt_status_next : std_logic_vector(AXIS_TDATA_WIDTH-1 downto 0);

  signal trig_cnt_reg, trig_cnt_next     : unsigned(AXIS_TDATA_WIDTH-1 downto 0); 
  signal cont_bines_reg, cont_bines_next : unsigned(AXIS_TDATA_WIDTH-1 downto 0); 

  --Charge signals
  signal charge1_reg, charge1_next       : unsigned(ADC_DATA_WIDTH-1 downto 0);
  signal charge2_reg, charge2_next       : unsigned(ADC_DATA_WIDTH-1 downto 0);

  --FSM signals
  type state_t is (ST_IDLE,
                      ST_ATT_TR,
                      ST_SEND_TR_STATUS,
                      ST_SEND_CNT_STATUS,
                      ST_ATT_SUBTR,
                      ST_ATT_PPS);
  signal state_reg, state_next: state_t;

  signal wr_count_reg, wr_count_next : unsigned(7 downto 0);
  signal data_to_fifo_reg, data_to_fifo_next : std_logic_vector(AXIS_TDATA_WIDTH-1 downto 0);
  signal axis_tvalid, wr_fifo_en_next  : std_logic;
  signal status : std_logic_vector(2 downto 0);

  signal axis_tready : std_logic;

  signal trig_lvl_a, trig_lvl_b       : std_logic_vector(AXIS_TDATA_WIDTH/2-1 downto 0);
  signal subtrig_lvl_a, subtrig_lvl_b : std_logic_vector(AXIS_TDATA_WIDTH/2-1 downto 0);

begin
    
  trig_lvl_a <= trig_lvl_i(AXIS_TDATA_WIDTH/2-1 downto 0);
  trig_lvl_b <= trig_lvl_i(AXIS_TDATA_WIDTH-1 downto AXIS_TDATA_WIDTH/2);

  subtrig_lvl_a <= subtrig_lvl_i(AXIS_TDATA_WIDTH/2-1 downto 0);
  subtrig_lvl_b <= subtrig_lvl_i(AXIS_TDATA_WIDTH-1 downto AXIS_TDATA_WIDTH/2);
--------------------------------------------------------------------------
  -- false PPS
  process(aclk)
  begin
    if (rising_edge(aclk)) then
      if (aresetn = '0') then
        one_sec_cnt <= (others => '0');   
        clk_cnt_pps <= (others => '0');   
      else
        if (unsigned(one_sec_cnt) = CLK_FREQ-1) then
          one_sec_cnt <= (others => '0');
        else
          one_sec_cnt <= std_logic_vector(unsigned(one_sec_cnt) + 1);
        end if;
       
        -- false PPS is UP for 200 ms
        if (unsigned(one_sec_cnt) < CLK_FREQ/5) then
          false_pps <= '1';
        else
          false_pps <= '0';
        end if;
        
        if (one_clk_pps = '1') then 
          clk_cnt_pps <=  (others => '0');
        else
          clk_cnt_pps <= std_logic_vector(unsigned(clk_cnt_pps) + 1);
        end if;

      end if;
    end if;
  end process;

---------------------------------------------------------------------------
---------------------------------------------------------------------------
  --PPS MUX 
  pps <=  false_pps when (gpsen_i = '1') else pps_i;

  false_pps_led_o <=  false_pps when (gpsen_i = '1') else '0';
---------------------------------------------------------------------------
---------------------------------------------------------------------------
  -- edge detector
  -- state register
  process(aclk)
  begin
    if (rising_edge(aclk)) then
    if (aresetn = '0') then
        pps_st_reg <= ZERO;
    else
        pps_st_reg <= pps_st_next;
    end if;
    end if;
  end process;

  -- next-state/output logic
  process(pps_st_reg, pps)
  begin
     pps_st_next <= pps_st_reg;
     one_clk_pps <= '0';
     case pps_st_reg is
        when ZERO =>
           if pps = '1' then
              pps_st_next <= EDGE;
           end if;
        when EDGE =>
           one_clk_pps <= '1';
           if pps = '1' then
              pps_st_next <= ONE;
           else
              pps_st_next <= ZERO;
           end if;
        when ONE =>
           if pps = '0' then
              pps_st_next <= ZERO;
           end if;
     end case;
  end process;
-----------------------------------------------------------------------------

-----------------------------------------------------------------------------

  -- data registers for a second
  process(aclk)
  begin
    for i in METADATA_ARRAY_LENGTH-1 downto 0 loop
      if (rising_edge(aclk)) then
      if (aresetn = '0') then
        array_pps_reg(i) <= (others => '0');
      else
        array_pps_reg(i) <= array_pps_next(i);
      end if;
      end if;
    end loop;
  end process;
  --next state logic
--  array_pps_next(METADATA_ARRAY_LENGTH-10)<= x"FFFFFFFF" when (one_clk_pps = '1') else array_pps_reg(METADATA_ARRAY_LENGTH-10);
--  array_pps_next(METADATA_ARRAY_LENGTH-9)<= "11" & "000" & std_logic_vector(clk_cnt_pps(26 downto 0)) when (one_clk_pps = '1') else array_pps_reg(METADATA_ARRAY_LENGTH-9);
--  array_pps_next(METADATA_ARRAY_LENGTH-8)<= "11" & "001" & "00000000000" & ptemperatura when (one_clk_pps = '1') else array_pps_reg(METADATA_ARRAY_LENGTH-8);
--  array_pps_next(METADATA_ARRAY_LENGTH-7)<= "11" & "010" & "00000000000" & ppresion when (one_clk_pps = '1') else array_pps_reg(METADATA_ARRAY_LENGTH-7);
--  array_pps_next(METADATA_ARRAY_LENGTH-6)<= "11" & "011" & "000" & phora & pminutos & psegundos when (one_clk_pps = '1') else array_pps_reg(METADATA_ARRAY_LENGTH-6);
--  array_pps_next(METADATA_ARRAY_LENGTH-5)<= "11" & "100" & "000" & latitude1_port & latitude2_port & latitude3_port when (one_clk_pps = '1') else array_pps_reg(METADATA_ARRAY_LENGTH-5);
--  array_pps_next(METADATA_ARRAY_LENGTH-4)<= "11" & "100" & "001" & longitude1_port & longitude2_port & latitude4_port when (one_clk_pps = '1') else array_pps_reg(METADATA_ARRAY_LENGTH-4);
--  array_pps_next(METADATA_ARRAY_LENGTH-3)<= "11" & "100" & "010" & ellipsoid1_port & longitude3_port & longitude4_port when (one_clk_pps = '1') else array_pps_reg(METADATA_ARRAY_LENGTH-3);
--  array_pps_next(METADATA_ARRAY_LENGTH-2)<= "11" & "100" & "011" & ellipsoid2_port & ellipsoid3_port & ellipsoid4_port when (one_clk_pps = '1') else array_pps_reg(METADATA_ARRAY_LENGTH-2);
--  array_pps_next(METADATA_ARRAY_LENGTH-1)<= "11" & "100" & "100" & num_track_sat_port & num_vis_sat_port & rsf_port when (one_clk_pps = '1') else array_pps_reg(METADATA_ARRAY_LENGTH-1);

  array_pps_next(METADATA_ARRAY_LENGTH-10)<= x"FFFFFFFF" when (one_clk_pps = '1') else array_pps_reg(METADATA_ARRAY_LENGTH-10);
  array_pps_next(METADATA_ARRAY_LENGTH-9)<= "11" & "000" & std_logic_vector(clk_cnt_pps(26 downto 0)) when (one_clk_pps = '1') else array_pps_reg(METADATA_ARRAY_LENGTH-9);
  array_pps_next(METADATA_ARRAY_LENGTH-8)<= "11" & "001" & "00000000000" & trig_lvl_i(AXIS_TDATA_WIDTH/2-1 downto 0) when (one_clk_pps = '1') else array_pps_reg(METADATA_ARRAY_LENGTH-8);
  array_pps_next(METADATA_ARRAY_LENGTH-7)<= "11" & "010" & "00000000000" & trig_lvl_i(AXIS_TDATA_WIDTH/2-1 downto 0) when (one_clk_pps = '1') else array_pps_reg(METADATA_ARRAY_LENGTH-7);
  array_pps_next(METADATA_ARRAY_LENGTH-6)<= "11" & "011" & "00000000000" & trig_lvl_i(AXIS_TDATA_WIDTH/2-1 downto 0) when (one_clk_pps = '1') else array_pps_reg(METADATA_ARRAY_LENGTH-6);
  array_pps_next(METADATA_ARRAY_LENGTH-5)<= "11" & "100" & "00000000000" & trig_lvl_i(AXIS_TDATA_WIDTH/2-1 downto 0) when (one_clk_pps = '1') else array_pps_reg(METADATA_ARRAY_LENGTH-5);
  array_pps_next(METADATA_ARRAY_LENGTH-4)<= "11" & "100" & "001" & "00000000" & trig_lvl_i(AXIS_TDATA_WIDTH/2-1 downto 0) when (one_clk_pps = '1') else array_pps_reg(METADATA_ARRAY_LENGTH-4);
  array_pps_next(METADATA_ARRAY_LENGTH-3)<= "11" & "100" & "010" & "00000000" & trig_lvl_i(AXIS_TDATA_WIDTH/2-1 downto 0) when (one_clk_pps = '1') else array_pps_reg(METADATA_ARRAY_LENGTH-3);
  array_pps_next(METADATA_ARRAY_LENGTH-2)<= "11" & "100" & "011" & "00000000" & trig_lvl_i(AXIS_TDATA_WIDTH/2-1 downto 0) when (one_clk_pps = '1') else array_pps_reg(METADATA_ARRAY_LENGTH-2);
  array_pps_next(METADATA_ARRAY_LENGTH-1)<= "11" & "100" & "100" & "00000000" & trig_lvl_i(AXIS_TDATA_WIDTH/2-1 downto 0) when (one_clk_pps = '1') else array_pps_reg(METADATA_ARRAY_LENGTH-1);
------------------------------------------------------------------------------------------------------

------------------------------------------------------------------------------------------------------
  --data acquisition for each channel
  process(aclk)
  begin
    for i in (DATA_ARRAY_LENGTH-1) downto 0 loop
      if (rising_edge(aclk)) then
      if (aresetn = '0') then
        adc_dat_a_reg(i) <= (others=>'0');
        adc_dat_b_reg(i) <= (others=>'0');
      else
        adc_dat_a_reg(i) <= adc_dat_a_next(i);
        adc_dat_b_reg(i) <= adc_dat_b_next(i);
      end if;
      end if;
      -- next state logic
      if (i = (DATA_ARRAY_LENGTH-1)) then
        adc_dat_a_next(i) <= s_axis_tdata(AXIS_TDATA_WIDTH/2 - 1 downto 0);
        adc_dat_b_next(i) <= s_axis_tdata(AXIS_TDATA_WIDTH - 1 downto AXIS_TDATA_WIDTH/2); 
      else
        adc_dat_a_next(i) <= adc_dat_a_reg(i+1);
        adc_dat_b_next(i) <= adc_dat_b_reg(i+1);
      end if;
    end loop;
  end process;

-----------------------------------------------------------------------------------------------------

-----------------------------------------------------------------------------------------------------
  --trigger
  process(aclk)
  begin
    if (rising_edge(aclk)) then
    if (aresetn = '0') then
      tr_status_reg  <= (others => '0');
      cnt_status_reg <= (others => '0');
      trig_cnt_reg   <= (others => '0');
    else
      tr_status_reg  <= tr_status_next;
      cnt_status_reg <= cnt_status_next;
      trig_cnt_reg   <= trig_cnt_next;
    end if;
    end if;
  end process;
  -- The trigger is at bin 4 because we loose a clock pulse in the state machine
  -- next state logic
  tr1_s <=  '1' when ((signed(adc_dat_a_reg(3)) >= signed(trig_lvl_a)) and
                      (signed(adc_dat_a_reg(2)) < signed(trig_lvl_a)) and
                      (signed(adc_dat_a_reg(1)) < signed(trig_lvl_a))) else
                '0';
  tr2_s <=  '1' when ((signed(adc_dat_b_reg(3)) >= signed(trig_lvl_b)) and
                      (signed(adc_dat_b_reg(2)) < signed(trig_lvl_b)) and
                      (signed(adc_dat_b_reg(1)) < signed(trig_lvl_b))) else
                '0';
  tr_s <= '1' when  ((tr1_s = '1') or (tr2_s = '1')) else '0';

  tr_status_next <=   "010" & tr2_s & tr1_s & std_logic_vector(clk_cnt_pps(26 downto 0)) when (tr_s = '1') else
                      tr_status_reg;
  cnt_status_next <=  "10" & std_logic_vector(trig_cnt_reg(AXIS_TDATA_WIDTH-3 downto 0)) when (tr_s = '1') else
                      cnt_status_reg;

  trig_cnt_next <= trig_cnt_reg + 1 when (tr_s = '1') else
                   trig_cnt_reg;

----------------------------------------------------------------------------------------------------------

----------------------------------------------------------------------------------------------------------
  --sub-trigger: we test for a sub-trigger and we must not have a trigger in the next two clocks
  process(aclk)
  begin
    if (rising_edge(aclk)) then
    if (aresetn = '0') then
      charge1_reg <= (others => '0');
      charge2_reg <= (others => '0');
      array_scalers_reg(SUBTRIG_ARRAY_LENGTH-1) <= (others => '0');
      array_scalers_reg(SUBTRIG_ARRAY_LENGTH-2) <= (others => '0');
      array_scalers_reg(SUBTRIG_ARRAY_LENGTH-3) <= (others => '0');
    else
      charge1_reg <= charge1_next;
      charge2_reg <= charge2_next;
      array_scalers_reg(SUBTRIG_ARRAY_LENGTH-1) <= array_scalers_next(SUBTRIG_ARRAY_LENGTH-1);
      array_scalers_reg(SUBTRIG_ARRAY_LENGTH-2) <= array_scalers_next(SUBTRIG_ARRAY_LENGTH-2);
      array_scalers_reg(SUBTRIG_ARRAY_LENGTH-3) <= array_scalers_next(SUBTRIG_ARRAY_LENGTH-3);
    end if;
    end if;
  end process;
  -- next state logic
  subtr1_s <= '1' when signed(adc_dat_a_reg(2)) >= signed(subtrig_lvl_a) and
                      signed(adc_dat_a_reg(1)) < signed(adc_dat_a_reg(2)) and
                      (signed(adc_dat_a_reg(3)) < signed(adc_dat_a_reg(2)) or
                      (signed(adc_dat_a_reg(3)) = signed(adc_dat_a_reg(2)) and
                      signed(adc_dat_a_reg(4)) < signed(adc_dat_a_reg(2)))) and
                      signed(adc_dat_a_reg(2)) < signed(trig_lvl_a) and
                      signed(adc_dat_a_reg(3)) < signed(trig_lvl_a) and
                      signed(adc_dat_a_reg(4)) < signed(trig_lvl_a) else
                    '0';
  subtr2_s <= '1' when signed(adc_dat_b_reg(2)) >= signed(subtrig_lvl_b) and
                      signed(adc_dat_b_reg(1)) < signed(adc_dat_b_reg(2)) and
                      (signed(adc_dat_b_reg(3)) < signed(adc_dat_b_reg(2)) or
                      (signed(adc_dat_b_reg(3)) = signed(adc_dat_b_reg(2)) and
                      signed(adc_dat_b_reg(4)) < signed(adc_dat_b_reg(2)))) and
                      signed(adc_dat_b_reg(2)) < signed(trig_lvl_b) and
                      signed(adc_dat_b_reg(3)) < signed(trig_lvl_b) and
                      signed(adc_dat_b_reg(4)) < signed(trig_lvl_b) else
                    '0';
  subtr_s <=  '1' when  ((subtr1_s = '1') or (subtr2_s = '1')) else '0';

  charge1_next <= charge1_reg + adc_dat_a_reg'left - adc_dat_a_reg'right;
  charge2_next <= charge2_reg + adc_dat_b_reg'left - adc_dat_b_reg'right;

  array_scalers_next(SUBTRIG_ARRAY_LENGTH-1) <= "010" & subtr2_s & subtr1_s & std_logic_vector(clk_cnt_pps(26 downto 0)) when (subtr_s = '1') else
                                              array_scalers_reg(SUBTRIG_ARRAY_LENGTH-1);
  array_scalers_next(SUBTRIG_ARRAY_LENGTH-2) <= "0000" & std_logic_vector(charge1_reg) & std_logic_vector(charge2_reg) when (subtr_s = '1') else
                                              array_scalers_reg(SUBTRIG_ARRAY_LENGTH-2); --charge values per channel
  array_scalers_next(SUBTRIG_ARRAY_LENGTH-3) <= "0000" & adc_dat_a_reg(2)(AXIS_TDATA_WIDTH/2-PADDING_WIDTH-1 downto 0) & adc_dat_b_reg(2)(AXIS_TDATA_WIDTH/2-PADDING_WIDTH-1 downto 0) when (subtr_s = '1') else
                                              array_scalers_reg(SUBTRIG_ARRAY_LENGTH-3); --we send the pulse maximum too

----------------------------------------------------------------------------------------------------------------

----------------------------------------------------------------------------------------------------------------
  -- FSM controlling all
  --================================================================
  -- state and data registers
  --================================================================
  process (aclk)
  begin
    if (rising_edge(aclk)) then
    if (aresetn = '0') then
      state_reg      <= ST_IDLE;
      wr_count_reg   <= (others => '0');
      data_to_fifo_reg <= (others => '0');
    else
      state_reg      <= state_next;
      wr_count_reg   <= wr_count_next;
      data_to_fifo_reg <= data_to_fifo_next;
    end if;
    end if;
  end process;
  --=================================================================
  --next-state logic & data path functional units/routing
  --=================================================================
  process(state_reg, status, wr_count_reg)
  begin
    state_next        <= state_reg;                -- default 
    axis_tvalid       <= '0';                 -- default disable fifo write
    wr_count_next     <= wr_count_reg;
    data_to_fifo_next <= data_to_fifo_reg;  -- default 
    axis_tready       <= '1';
    case state_reg is
      when ST_IDLE =>
        if (s_axis_tvalid = '1') then     
          case status is
            when "001" | "011" | "101" | "111" => -- priority is for PPS data every second
              state_next <= ST_ATT_PPS;
            when "100" | "110" =>
              state_next <= ST_ATT_TR;
            when "010" =>
              state_next <= ST_ATT_SUBTR;
            when others => --"000"
              state_next <= ST_IDLE;
          end case;
        else
          state_next <= ST_IDLE;
        end if;

      --we send adc data because we have a trigger
      when ST_ATT_TR =>
        axis_tready <= '0';
        axis_tvalid <= '1';
        if (wr_count_reg = (DATA_ARRAY_LENGTH - 1)) then
          wr_count_next     <= (others => '0');
          state_next <= ST_SEND_TR_STATUS;
        else
          if (m_axis_tready = '1') then
            wr_count_next <= wr_count_reg + 1;
            data_to_fifo_next <= "00" &  not adc_dat_b_reg(0)(AXIS_TDATA_WIDTH/2-PADDING_WIDTH-1 downto 0) & "00" & not adc_dat_a_reg(0)(AXIS_TDATA_WIDTH/2-PADDING_WIDTH-1 downto 0);
          end if;
          state_next <= ST_ATT_TR;
        end if;

      when ST_SEND_TR_STATUS =>
        axis_tready <= '0';
        axis_tvalid <= '1';
        if (m_axis_tready = '1') then
          data_to_fifo_next <= tr_status_reg;
          state_next <= ST_SEND_CNT_STATUS;
        else
          state_next <= ST_SEND_TR_STATUS;
        end if;

      when ST_SEND_CNT_STATUS =>
        axis_tready <= '0';
        axis_tvalid <= '1';
        if (m_axis_tready = '1') then
          data_to_fifo_next <= cnt_status_reg;
          state_next <= ST_IDLE;
        else
          state_next <= ST_SEND_CNT_STATUS;
        end if;

      when ST_ATT_SUBTR =>
        axis_tready <= '0';
        axis_tvalid <= '1';
        if (wr_count_reg = (SUBTRIG_ARRAY_LENGTH - 1)) then
          wr_count_next     <= (others => '0');
          state_next <= ST_IDLE;
        else 
          if (m_axis_tready = '1') then
            wr_count_next <= wr_count_reg + 1;
            data_to_fifo_next <= array_scalers_reg(to_integer(wr_count_reg));
          end if;
          state_next <= ST_ATT_SUBTR;
        end if;

      when ST_ATT_PPS =>
        axis_tready <= '0';
        axis_tvalid <= '1';
        if (wr_count_reg = (METADATA_ARRAY_LENGTH - 1)) then
          wr_count_next     <= (others => '0');
          state_next <= ST_IDLE;
        else
          if (m_axis_tready = '1') then
            wr_count_next <= wr_count_reg + 1;
            data_to_fifo_next <= array_pps_reg(to_integer(wr_count_reg));
          end if;
          state_next <= ST_ATT_PPS;
        end if;
   end case;
  end process;

  status <= tr_s & subtr_s & one_clk_pps;
  s_axis_tready <= axis_tready;
  m_axis_tdata <= data_to_fifo_reg;
  m_axis_tvalid <= axis_tvalid;

end architecture rtl;

