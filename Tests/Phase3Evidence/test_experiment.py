import copy
import json
import tempfile
import unittest
from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[2]/'scripts'))
from test_compare import capture, report
import phase4_experiment

class ExperimentTests(unittest.TestCase):
    def test_plan_keeps_device_execution_pending(self):
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder)/'session.json'
            path.write_text(json.dumps(phase4_experiment.plan()))
            result=phase4_experiment.analyze(path)
            self.assertEqual(result['executionStatus'],'awaiting_device')
            self.assertEqual(result['globalCanvasEvidence'],'unverified')

    def perform(self,restore_bounds=None,after_restore_time=3):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);manifest=phase4_experiment.plan()
            samples=[capture(1),capture(2),capture(after_restore_time)]
            samples[1]['geometry']['bounds']={'width':8,'height':16}
            if restore_bounds is not None:samples[2]['geometry']['bounds']=restore_bounds
            for name,sample in zip(('before','changed','restored'),samples):
                filename=name+'.json';(root/filename).write_text(json.dumps(report(sample)))
                manifest['captures'][name]=filename
            path=root/'session.json';path.write_text(json.dumps(manifest))
            return phase4_experiment.analyze(path)

    def test_three_states_measure_logical_change_and_geometry_return(self):
        result=self.perform()
        self.assertEqual(result['restorationGeometry'],'returned_within_measured_fields')
        self.assertEqual(result['change']['geometry']['bounds']['comparison'],'different')
        self.assertEqual(result['executionStatus'],'awaiting_external_captures')
        self.assertEqual(result['globalCanvasEvidence'],'unverified')

    def test_restoration_mismatch_is_preserved(self):
        result=self.perform({'width':9,'height':18})
        self.assertEqual(result['restorationGeometry'],'different')

    def test_restoration_must_follow_changed_capture(self):
        with self.assertRaises(phase4_experiment.EvidenceError):self.perform(after_restore_time=1)

    def test_missing_dimension_keeps_restoration_indeterminate(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);manifest=phase4_experiment.plan()
            for index,name in enumerate(('before','changed','restored'),1):
                data=capture(index)
                if name=='restored':del data['geometry']['currentMode']
                (root/(name+'.json')).write_text(json.dumps(report(data)))
                manifest['captures'][name]=name+'.json'
            path=root/'plan.json';path.write_text(json.dumps(manifest))
            self.assertEqual(phase4_experiment.analyze(path)['restorationGeometry'],'indeterminate')

if __name__=='__main__':unittest.main()
