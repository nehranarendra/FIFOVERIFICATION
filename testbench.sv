`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: NONE
// Engineer: NARENDRA KUMAR NEHRA
// 
// Create Date: 22.07.2024 17:42:40
// Design Name: FIFO VERIFICATION USING SYSTEM VERILOG
// Module Name: testbench
// Project Name: 
// Target Devices: 
// Tool Versions: VIVADO 2023.2
////////////////////////////////////////////////////////////////////////////////


class transaction;
  
  // Randomized bit for operation control (1 or 0)
  rand bit oper;
  
  // Read and write control bits
  bit rd, wr;

  // 8-bit data input
  bit [7:0] data_in;

  // Flags for full and empty status
  bit full, empty;

  // 8-bit data output
  bit [7:0] data_out;
  
  // Constraint to randomize 'oper' with 50% probability of 1 and 50%      probability of 0
  constraint oper_ctrl {  
    oper dist {1 :/ 50 , 0 :/ 50};
  }

endclass

//////////////////////////////////////////////////////////////////////////
class generator;

  // Transaction object to generate and send
  transaction tr; 

  // Mailbox for communication
  mailbox #(transaction) mbx;

  // Number of transactions to generate
  int count = 0;

  // Iteration counter
  int i = 0;

  // Event to signal when to send the next transaction
  event next;

  // Event to convey completion of requested number of transactions
  event done;
  
  // Constructor to initialize mailbox and transaction object
  function new(mailbox #(transaction) mbx);
    this.mbx = mbx;
    tr = new();
  endfunction;
  
  // Task to generate and send transactions
  task run();
    repeat (count) begin
      assert (tr.randomize()) else $error("Randomization failed");
      i++;
      mbx.put(tr);
      $display("[GEN] : Oper : %0d iteration : %0d", tr.oper, i);
      @(next);
    end
    -> done;
  endtask

endclass


////////////////////////////////////////////////////////////////////////////////
class driver;

  // Virtual interface to the FIFO
  virtual fifo_if fif;

  // Mailbox for communication
  mailbox #(transaction) mbx;

  // Transaction object for communication
  transaction datac;
  
  // Constructor to initialize the mailbox
  function new(mailbox #(transaction) mbx);
    this.mbx = mbx;
  endfunction;

  // Reset the DUT
  task reset();
    fif.rst <= 1'b1;
    fif.rd <= 1'b0;
    fif.wr <= 1'b0;
    fif.data_in <= 0;
    repeat (5) @(posedge fif.clock);
    fif.rst <= 1'b0;
    $display("[DRV] : DUT Reset Done");
    $display("------------------------------------------");
  endtask;

  // Write data to the FIFO
  task write();
    @(posedge fif.clock);
    fif.rst <= 1'b0;
    fif.rd <= 1'b0;
    fif.wr <= 1'b1;
    fif.data_in <= $urandom_range(1, 10);
    @(posedge fif.clock);
    fif.wr <= 1'b0;
    $display("[DRV] : DATA WRITE data: %0d", fif.data_in);
    @(posedge fif.clock);
  endtask;

  // Read data from the FIFO
  task read();
    @(posedge fif.clock);
    fif.rst <= 1'b0;
    fif.rd <= 1'b1;
    fif.wr <= 1'b0;
    @(posedge fif.clock);
    fif.rd <= 1'b0;
    $display("[DRV] : DATA READ");
    @(posedge fif.clock);
  endtask;

  // Apply random stimulus to the DUT
  task run();
    forever begin
      mbx.get(datac);
      if (datac.oper == 1'b1)
        write();
      else
        read();
    end
  endtask;

endclass
///////////////////////////////////////////////////////////////////////

class monitor;

  // Virtual interface to the FIFO
  virtual fifo_if fif;

  // Mailbox for communication
  mailbox #(transaction) mbx;

  // Transaction object for monitoring
  transaction tr;
  
  // Constructor to initialize the mailbox
  function new(mailbox #(transaction) mbx);
    this.mbx = mbx;
  endfunction;

  // Task to monitor FIFO operations and transactions
  task run();
    tr = new();
    
    forever begin
      repeat (2) @(posedge fif.clock);
      tr.wr = fif.wr;
      tr.rd = fif.rd;
      tr.data_in = fif.data_in;
      tr.full = fif.full;
      tr.empty = fif.empty;
      @(posedge fif.clock);
      tr.data_out = fif.data_out;
      
      mbx.put(tr);
      $display("[MON] : Wr:%0d rd:%0d din:%0d dout:%0d full:%0d empty:%0d", 
               tr.wr, tr.rd, tr.data_in, tr.data_out, tr.full, tr.empty);
    end
  endtask;

endclass


//////////////////////////////////////////////////////////////////////////////
class scoreboard;

  // Mailbox for communication
  mailbox #(transaction) mbx;

  // Transaction object for monitoring
  transaction tr;

  // Event to signal the next operation
  event next;

  // Array to store written data
  bit [7:0] din[$];

  // Temporary data storage
  bit [7:0] temp;

  // Error count
  int err = 0;

  // Constructor to initialize the mailbox
  function new(mailbox #(transaction) mbx);
    this.mbx = mbx;
  endfunction;

  // Task to monitor transactions and verify data
  task run();
    forever begin
      mbx.get(tr);
      $display("[SCO] : Wr:%0d rd:%0d din:%0d dout:%0d full:%0d empty:%0d", 
               tr.wr, tr.rd, tr.data_in, tr.data_out, tr.full, tr.empty);
      
      if (tr.wr == 1'b1) begin
        if (tr.full == 1'b0) begin
          din.push_front(tr.data_in);
          $display("[SCO] : DATA STORED IN QUEUE : %0d", tr.data_in);
        end else begin
          $display("[SCO] : FIFO is full");
        end
        $display("--------------------------------------"); 
      end
    
      if (tr.rd == 1'b1) begin
        if (tr.empty == 1'b0) begin  
          temp = din.pop_back();
          
          if (tr.data_out == temp)
            $display("[SCO] : DATA MATCH");
          else begin
            $error("[SCO] : DATA MISMATCH");
            err++;
          end
        end else begin
          $display("[SCO] : FIFO IS EMPTY");
        end
        
        $display("--------------------------------------"); 
      end
      
      -> next;
    end
  endtask;

endclass
/////////////////////////////////////////////////////////////////////////////
class environment;

  generator gen;
  driver drv;
  monitor mon;
  scoreboard sco;
  mailbox #(transaction) gdmbx;  // Generator + Driver mailbox
  mailbox #(transaction) msmbx;  // Monitor + Scoreboard mailbox
  event nextgs;
  virtual fifo_if fif;
  
  // Constructor to initialize components and mailboxes
  function new(virtual fifo_if fif);
    gdmbx = new();
    gen = new(gdmbx);
    drv = new(gdmbx);
    msmbx = new();
    mon = new(msmbx);
    sco = new(msmbx);
    this.fif = fif;
    drv.fif = this.fif;
    mon.fif = this.fif;
    gen.next = nextgs;
    sco.next = nextgs;
  endfunction
  
  // Task to reset the DUT
  task pre_test();
    drv.reset();
  endtask
  
  // Task to run the test
  task test();
    fork
      gen.run();
      drv.run();
      mon.run();
      sco.run();
    join_any
  endtask
  
  // Task to conclude the test
  task post_test();
    wait(gen.done.triggered);
    $display("---------------------------------------------");
    $display("Error Count : %0d", sco.err);
    $display("---------------------------------------------");
    $finish();
  endtask
  
  // Task to run the entire test sequence
  task run();
    pre_test();
    test();
    post_test();
  endtask

endclass

///////////////////////////////////////////////////////

module testbench;
    
  fifo_if fif();
  FIFO dut (
    fif.clock,
    fif.rst,
    fif.wr,
    fif.rd,
    fif.data_in,
    fif.data_out,
    fif.empty,
    fif.full
  );
    
  initial begin
    fif.clock <= 0;
  end
    
  always #10 fif.clock <= ~fif.clock;
    
  environment env;
    
  initial begin
    env = new(fif);
    env.gen.count = 10;
    env.run();
  end
    
  initial begin
    $dumpfile("dump.vcd");
    $dumpvars;
  end

endmodule
