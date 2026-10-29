import tempfile
import unittest
import uuid
from service import Service, WEEK
from push import Worker, PushFailure

class Transport:
    def __init__(self): self.calls=[]; self.fail=None
    def send(self, device, thread, message, expires):
        self.calls.append((device['id'],thread,message))
        if self.fail: raise self.fail

class PushTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.now=1800000000.;self.mail={};self.transport=Transport()
        self.service=Service(self.temp.name+'/db','secret'*8,lambda e,c:self.mail.update({e:c}),lambda:self.now,{'fcm':self.transport})
        self.worker=Worker(self.service,{'fcm':self.transport})
        self.sender=self.login('sender@example.com');self.owner=self.login('owner@example.com')
        self.call(self.owner,'POST','/me/plates',plate='AB1234',authorisedDriver=True)
    def tearDown(self):self.temp.cleanup()
    def login(self,email):
        self.service.dispatch('POST','/auth/start',{'email':email},ip=email)
        return self.service.dispatch('POST','/auth/verify',{'email':email,'code':self.mail[email]},ip=email)['token']
    def call(self,session,method,path,**body):return self.service.dispatch(method,path,body,session)
    def device(self,session):
        ident=str(uuid.uuid4());self.call(session,'PUT','/me/devices/'+ident,provider='fcm',token=str(uuid.uuid4()));return ident
    def send(self):return self.call(self.sender,'POST','/threads',plate='AB1234',text='留意入返咪錶',idempotencyKey=str(uuid.uuid4()))
    def test_each_device_once_and_late_devices_do_not_get_stale_pushes(self):
        self.device(self.owner);self.device(self.owner);self.send();self.device(self.owner);self.worker.tick();self.worker.tick()
        self.assertEqual(2,len(self.transport.calls))
        self.device(self.owner);self.worker.tick();self.assertEqual(2,len(self.transport.calls))
    def test_retry_then_accept_and_invalid_device_cleanup(self):
        self.device(self.owner);self.send();self.transport.fail=PushFailure('temporary',retryable=True)
        self.worker.tick();self.assertEqual(1,len(self.transport.calls));self.worker.tick();self.assertEqual(1,len(self.transport.calls))
        self.now+=20;self.transport.fail=None;self.worker.tick();self.assertEqual(2,len(self.transport.calls))
        self.send();self.transport.fail=PushFailure('unregistered',invalid_token=True);self.worker.tick()
        with self.service.db() as db:self.assertEqual(0,db.execute('SELECT count(*) FROM devices').fetchone()[0])
    def test_logout_unbind_and_expiry_cancel_delivery(self):
        self.device(self.owner);self.send();self.call(self.owner,'POST','/auth/logout');self.worker.tick()
        self.assertEqual([],self.transport.calls)
        self.owner=self.login_later('owner@example.com');self.device(self.owner);self.send()
        self.call(self.owner,'DELETE','/me/plates/AB1234');self.worker.tick();self.assertEqual([],self.transport.calls)
        self.call(self.owner,'POST','/me/plates',plate='AB1234',authorisedDriver=True);self.send();self.now+=WEEK;self.worker.tick()
        self.assertEqual([],self.transport.calls)
        with self.service.db() as db:self.assertEqual(0,db.execute('SELECT count(*) FROM push_jobs').fetchone()[0])
    def login_later(self,email):self.now+=61;return self.login(email)
    def test_blocks_are_rechecked_before_delivery(self):
        self.device(self.owner);self.send();sender_id=self.service.authenticate(self.sender)
        self.call(self.owner,'POST','/blocks',userId=sender_id);self.worker.tick();self.assertEqual([],self.transport.calls)

if __name__=='__main__':unittest.main()
