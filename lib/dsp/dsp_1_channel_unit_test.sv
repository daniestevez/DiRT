//-------------------------------------------------------------------------------
// File:    dsp_1_channel_unit_test.sv
//
// Author:  Ian Buckley, Ion Concepts LLC
//
// Description:
// Unit tests for dsp_1_channel
//
// License: CERN-OHL-P (See LICENSE.md)
//
//-------------------------------------------------------------------------------
`include "global_defs.svh"
`include "svunit_defines.svh"
`include "drat_protocol.sv"
`include "dsp_1_channel.sv"

module dsp_1_channel_unit_test;

   import drat_protocol::*;
   import svunit_pkg::svunit_testcase;
   import axis_siggen_pkg::*;
   string name = "dsp_1_channel_ut";
   svunit_testcase svunit_ut;

   timeunit 1ns;
   timeprecision 1ps;

   localparam C_SIGGEN_WAVEFORM = axis_siggen_pkg::RAMP;

   logic  clk;
   logic  rst;

   axis_t #(.WIDTH(32)) axis_rx_sample(.clk(clk));
   axis_t #(.WIDTH(32)) axis_tx_sample(.clk(clk));

   pkt_stream_t axis_tx_packet(.clk(clk));
   pkt_stream_t axis_rx_packet(.clk(clk));

   logic [63:0] system_time;

   // CSRs for axis_siggen on test bench
   logic       siggen_enable;
   logic [31:0] siggen_phase_inc;
   logic [7:0]  siggen_waveform;


   //
   // CSR
   //
   logic       csr_tx_deframer_enable;
   logic       csr_tx_status_enable;
   logic       csr_tx_consumption_enable;
   logic       csr_tx_control_enable;
   // FlowID to me used in status packet header
   logic [31:0] csr_tx_status_flow_id;
   // FlowID to me used in consumption packet header
   logic [31:0] csr_tx_consumption_flow_id;
   // Error policy register
   logic        csr_tx_error_policy_next_packet;
   // Enable stream_to_pkt block
   logic        csr_stream_to_pkt_enable;
   // Packet size expressed in number of samples
   logic [13:0] csr_rx_packet_size;
   // DRaT Flow ID for this flow (union of src + dst)
   logic [31:0] csr_rx_flow_id;
   // Time increment per packet of size packet_size
   logic [15:0] csr_rx_time_per_pkt;
   // Number of samples in a burst. Write to zero for infinite burst.
   logic [47:0] csr_rx_burst_size;
   // Assert this signal for a single cycle to trigger an async return to idle.
   logic        csr_rx_abort;
   // Status Flags
   logic        csr_stream_to_pkt_idle; // Assert when state machine is idle

   // Watchdog
   int 		timeout;

   //
   // Generate clk
   //
   initial begin
      clk <= 1'b1;
   end

   always begin
      #5 clk <= ~clk;
   end

   //-------------------------------------------------------------------------------
   // Siggen provides waveform to RX
   //-------------------------------------------------------------------------------
/*
   axis_siggen axis_siggen_i0
     (
      .clk(clk),
      .rst(rst),
      // Control/Status Regs (CSRs)
      .enable_in(siggen_enable),
      .phase_inc_in(siggen_phase_inc),
      .waveform_in(siggen_waveform),
      // Waveform output
      .axis_stream_out(axis_rx_sample)
      );
*/

   dsp_loopback
     #(
       .COUNT_SIZE(8)
       )
   dsp_loopback_i0
     (
      .clk(clk),
      .rst(rst),
      .axis_stream_in(axis_tx_sample),
      .axis_stream_out(axis_rx_sample)
      );

   //-------------------------------------------------------------------------------
   // Null Sink provides place to send DRaT packets
   //-------------------------------------------------------------------------------

   axis_null_sink axis_null_sink_i0
     (
      .in_axis(axis_rx_packet.axis)
      );

   //===================================
   // This is the UUT that we're
   // running the Unit Tests on
   //===================================
   dsp_1_channel
     #(
       .TX_DATA_FIFO_SIZE(12),  // Must be substantial for high TX rates and large MTU's
       .TX_STATUS_FIFO_SIZE(5), // Default to SRL32 implementation
       .RX_TIME_FIFO_SIZE(4),  // Default from axis_stream_to_pkt_wrapper
       .RX_SAMPLE_FIFO_SIZE(13),  // Default from axis_stream_to_pkt_wrapper
       .RX_PACKET_FIFO_SIZE(8),  // Default from axis_stream_to_pkt_wrapper
       .RX_DATA_FIFO_SIZE(10),
       .IQ_WIDTH(16)  // Default from axis_stream_to_pkt_wrapper
       )
   dsp_1_channel_i0
     (
      .clk(clk),
      .rst(rst),
      //
      // Control and Status Regs (CSR)
      //
      .csr_tx_deframer_enable(csr_tx_deframer_enable),
      .csr_tx_status_enable(csr_tx_status_enable),
      .csr_tx_consumption_enable(csr_tx_consumption_enable),
      .csr_tx_control_enable(csr_tx_control_enable),
      // FlowID to me used in status packet header
      .csr_tx_status_flow_id(csr_tx_status_flow_id),
      // FlowID to me used in consumption packet header
      .csr_tx_consumption_flow_id(csr_tx_consumption_flow_id),
      // Error policy register
      .csr_tx_error_policy_next_packet(csr_tx_error_policy_next_packet),
      // Enable stream_to_pkt block
      .csr_stream_to_pkt_enable(csr_stream_to_pkt_enable),
      // Packet size expressed in number of samples
      .csr_rx_packet_size(csr_rx_packet_size),
      // DRaT Flow ID for this flow (union of src + dst)
      .csr_rx_flow_id(csr_rx_flow_id),
      // Time increment per packet of size packet_size
      .csr_rx_time_per_pkt(csr_rx_time_per_pkt),
      // Number of samples in a burst. Write to zero for infinite burst.
      .csr_rx_burst_size(csr_rx_burst_size),
      // Assert this signal for a single cycle to trigger an async return to idle.
      .csr_rx_abort(csr_rx_abort),
      // Status Flags
      .csr_stream_to_pkt_idle(csr_stream_to_pkt_idle), // Assert when state machine is idle
      // System Time Input
      .system_time(system_time),
      // RX sample Input Bus
      .axis_rx_sample(axis_rx_sample),
      // TX Sample Output Bus
      .axis_tx_sample(axis_tx_sample),
      // DRaT packets in
      .axis_tx_packet(axis_tx_packet.axis),
      // DRaT packets out
      .axis_rx_packet(axis_rx_packet.axis)
      );

   //-----------------------------------------------------------------------------
   //
   // Time
   //
   // Single instance of time_source per FPGA provides system time for global use.
   // Should run on sample clock (or decimated version via RFDC)
   //-------------------------------------------------------------------------------

    always_ff @(posedge clk) begin
        if (rst) begin
            system_time <= 0;
        end else begin
            system_time <= system_time + 1;
        end
    end

   //===================================
   // Build
   //===================================
   function void build();
      svunit_ut = new(name);
   endfunction


   //===================================
   // Setup for running the Unit Tests
   //===================================
   task setup();
      svunit_ut.setup();
      /* Place Setup Code Here */
      // Reset UUT
      @(negedge clk);
      rst <= 1'b1;
      // Siggen
      siggen_enable = 0;
      siggen_phase_inc = 1 << 16;
      siggen_waveform = C_SIGGEN_WAVEFORM;

      // TX not used.
      csr_tx_deframer_enable = 0;
      csr_tx_status_enable = 0;
      csr_tx_consumption_enable = 0;
      csr_tx_control_enable = 0;
      // FlowID to me used in status packet header
      csr_tx_status_flow_id = 0;
      // FlowID to me used in consumption packet header
      csr_tx_consumption_flow_id = 0;
      // Error policy register
      csr_tx_error_policy_next_packet=1;

      // Rx Packet size expressed in number of samples
      csr_rx_packet_size = 10;
      // DRaT Flow ID for this flow (union of src + dst)
      csr_rx_flow_id = 'h12345678;
      // Time increment per packet of size packet_size
      csr_rx_time_per_pkt = 2560;
      // Number of samples in a burst. Write to zero for infinite burst.
      csr_rx_burst_size = 0;
      // Assert this signal for a single cycle to trigger an async return to idle.
      csr_rx_abort = 0;

      // Dissable stream_to_pkt block
      csr_stream_to_pkt_enable = 0;
      //
      repeat(10) @(negedge clk);
      rst <= 1'b0;
      //idle_all();
   endtask


   //===================================
   // Here we deconstruct anything we
   // need after running the Unit Tests
   //===================================
   task teardown();
      svunit_ut.teardown();
      /* Place Teardown Code Here */
   endtask

  //===================================
  // All tests are defined between the
  // SVUNIT_TESTS_BEGIN/END macros
  //
  // Each individual test must be
  // defined between `SVTEST(_NAME_)
  // `SVTEST_END
  //
  // i.e.
  //   `SVTEST(mytest)
  //     <test code>
  //   `SVTEST_END
  //===================================
  `SVUNIT_TESTS_BEGIN
     //-------------------------------------------------------------------------------
     // Simple Test. Just stream wave form into RX and throw DRaT packets away
     //
     // Configured as follows:
     // start_time = 1000
     // packet_size = 10 samples
     // flow_id = {INPUT,OUTPUT}
     // time_per_pkt = 10 (Sample_rate=clk_rate)
     // burst_size = 100 (10 packets)
     //
     //-------------------------------------------------------------------------------
   `SVTEST(stream_ramp)
   `INFO("Stream ramp of INT16_COMPLEX");
      fork
         begin: configure
            // TX not used.
            csr_tx_deframer_enable = 0;
            csr_tx_status_enable = 0;
            csr_tx_consumption_enable = 0;
            csr_tx_control_enable = 0;
            // FlowID to me used in status packet header
            csr_tx_status_flow_id = 0;
            // FlowID to me used in consumption packet header
            csr_tx_consumption_flow_id = 0;
            // Error policy register
            csr_tx_error_policy_next_packet=1;

            // Rx Packet size expressed in number of samples
            csr_rx_packet_size = 10;
            // DRaT Flow ID for this flow (union of src + dst)
            csr_rx_flow_id = 'h12345678;
            // Time increment per packet of size packet_size
            csr_rx_time_per_pkt = 2560;
            // Number of samples in a burst. Write to zero for infinite burst.
            csr_rx_burst_size = 0;
            // Assert this signal for a single cycle to trigger an async return to idle.
            csr_rx_abort = 0;
            @(negedge clk);
            // Enable stream_to_pkt block
            csr_stream_to_pkt_enable = 1;
            siggen_enable = 1;



         end // block: configure
         begin : watchdog_thread
	    timeout = 10000;
	    while(1) begin
	       //`FAIL_IF(timeout==0);
	       timeout = timeout - 1;
	       @(negedge clk);
	    end
            // Dissable stream_to_pkt block
            csr_stream_to_pkt_enable = 0;
         end
      join
     `SVTEST_END
   `SVUNIT_TESTS_END


endmodule // dsp_1_channel_unit_test