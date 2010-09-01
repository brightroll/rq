
It *tries* hard to

- insure message is in identical state every run

- avoid duplicate messages
  aka - there is a small chance that messages might be duplicated.

It *does not try* hard to guarantee ordering
  - messages might come in out-of-order. this may happen as a result
    of a failure in the system or operations repointing traffic
    to another rq

given the above, use timestamp versioning to insure an older message
doesn't over-write a newer message. if you see the same timestamp again
for a previously successful txn, it might be that ultra-ultra rare duplicate,
so drop it. 

- You must exit properly with the proper handshake. 

