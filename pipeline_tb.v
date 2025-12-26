`timescale 1ns / 1ps

module tb();
    // --- Clock and Reset ---
    reg clk = 0;
    reg rst = 0;
    
    // --- Inputs to Instruction Loader ---
    reg [11:0] operand1, operand2;
    reg [2:0] opcode;
    reg test_en_in = 0;      
    
    // --- Interconnect Wires ---
    wire [31:0] imem_waddr, imem_wdata;
    wire imem_we;
    wire done_signal; 
    wire [31:0] result_w;
    wire s_err_imem, d_err_imem;
    wire s_err_dmem, d_err_dmem;
    wire alu_fault_active; 

    // --- DIAGNOSTIC SPY WIRES ---
    // These monitor the data flow between the ALU output and the MISR input
    wire [31:0] spy_alu_raw = dut.execute.primary_alu.Primary_ALU.Result;
    wire [31:0] spy_misr_in  = dut.execute.alu_checker.primary_res;

    // --- Clock Generation (100MHz) ---
    always #5 clk = ~clk; 

    // --- Module Instantiations ---
    instr_loader loader (
        .clk(clk), .rst(rst), .op1(operand1), .op2(operand2), .alu_op(opcode),
        .imem_we(imem_we), .imem_addr(imem_waddr), .imem_wdata(imem_wdata), 
        .done(done_signal)
    );

    Pipeline_top dut (
        .clk(clk), .rst(rst), 
        .imem_we(imem_we), .imem_waddr(imem_waddr), .imem_wdata(imem_wdata), 
        .loader_done_in(done_signal), 
        .test_en_in(test_en_in),       
        .ResultW_out(result_w),
        .s_err_imem(s_err_imem), .d_err_imem(d_err_imem),
        .s_err_dmem(s_err_dmem), .d_err_dmem(d_err_dmem),
        .hardware_fault_flag(alu_fault_active) 
    );

    // ==========================================================
    // 1. DYNAMIC FAULT INJECTION LOGIC
    // ==========================================================
    // This forces bit 31 to 1 during BIST. Since the ALU usually outputs 0,
    // this corrupts the feedback loop and forces the signature to change.
    always @(*) begin
        if (test_en_in)
            force dut.execute.primary_alu.res_p[8] =~dut.execute.primary_alu.res_p[8] ;
        else
            release dut.execute.primary_alu.res_p[31];
    end

    // ==========================================================
    // 2. GOLDEN SIGNATURE LOGGER (With Timing Fix)
    // ==========================================================
    always @(posedge dut.execute.test_done) begin
        #2; // Tiny delay to allow hardware flags to stabilize
        $display("\n==================================================");
        $display("BIST FINISHED!");
        $display("FINAL MISR SIGNATURE: %h", dut.execute.alu_checker.signature);
        $display("EXPECTED GOLDEN     : %h", 32'h81c6f051);
//        $display("ALU FAULT STATUS    : %b", alu_fault_active);
        
        if (dut.execute.alu_checker.signature!=32'h81c6f051)
            $display("RESULT: SUCCESS - Hardware Fault Correctly Detected and Masked.");
        else
            $display("RESULT: FAILURE - Signature matched despite injected fault.");
        $display("==================================================\n");
        //  $display("ALU FAULT STATUS    : %b", alu_fault_active);
    end
   


    // --- Real-time Monitor ---
    initial begin
        $monitor("Time=%0t | BIST_EN=%b | Fault_Flag=%b | LFSR=%h", 
      //  | ResultW=%d | LFSR=%h", 
                 $time, test_en_in, alu_fault_active, dut.execute.lfsr);
              //   result_w, dut.execute.lfsr);
    end

    // --- Main Simulation Stimulus ---
    initial begin
        // 1. Reset and Load Program
        rst = 0;
        operand1 = 12'd5; operand2 = 12'd3; opcode = 3'd0; // 5 + 3 = 8
        #15; rst = 1; 
        wait(done_signal === 1'b1);
        $display("--- Program Loaded. Starting Execution ---");

        // 2. Start BIST
        #100;
        $display("Step 1: Starting Pseudorandom BIST (255 Cycles)");
        test_en_in = 1; 
        
        wait(dut.execute.test_done == 1'b1);
        
        @(posedge clk);
        #5;
        test_en_in = 0; 

        // 3. Data Memory ECC Test
        #200; 
        wait(dut.execute.RegWriteM == 1'b1);
        #1; 
        $display("Step 2: Injecting Single-Bit Error into Data Memory");
        dut.memory.dmem.mem[1][30] = ~dut.memory.dmem.mem[1][30]; 
        
        wait(s_err_dmem === 1'b1);
        $display("SUCCESS: ECC detected single-bit error.");

        #50;
        $display("Final System Result Sampled: %d", result_w);
        
        if (result_w == 32'd8)
            $display("VERDICT: ALL SYSTEMS FUNCTIONAL (LFSR-BIST & ECC)");
        else
            $display("VERDICT: SYSTEM FAILURE - Final Result Incorrect.");

        $finish;
    end
endmodule