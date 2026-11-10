Project 6: Direct-Mapped Cache Controller
Level: Intermediate
Objective: Design a direct-mapped cache controller and analyze cache hit/miss behavior using representative memory-access traces.
Architecture / Concepts: Memory hierarchy, temporal/spatial locality, tag/index/offset, cache hit/miss, hit ratio, miss ratio and AMAT.
Suggested Verilog Modules: Cache Data RAM; Tag RAM; Valid-Bit RAM; Address Decoder; Tag Comparator; Cache Controller FSM; Main-Memory Interface.
Suggested Parameters: A practical student configuration can use a small cache such as 1 KB with 16-byte blocks and 32-bit addresses; students may vary these parameters.
Implementation Workflow: Derive tag/index/offset fields; implement cache storage; implement lookup and refill; generate sequential, random and repeated accesses; calculate hit rate and AMAT.
Expected Deliverables: Cache RTL, controller FSM, memory-access trace, hit/miss report, AMAT calculation and synthesis results.
Evaluation Focus: Correct cache lookup/refill, valid-bit handling, hit/miss statistics and architectural analysis