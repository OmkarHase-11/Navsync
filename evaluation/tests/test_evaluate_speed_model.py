"""Synthetic complete-run evaluation; no installed IO-VNBD dependency."""

from contextlib import redirect_stdout, redirect_stderr
import csv
import io
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import numpy as np

from evaluation import evaluate_speed_model as module
from evaluation.evaluate_speed_model import (evaluate_predictions, validate_pairs, evaluate_holdout,
    leave_one_run_out, summarize_speed_bands, summarize_stationary_moving, export_results, main)


class EvaluationTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name)

    def pair(self, number, count=14):
        paths=[self.root/f'S-run{number}.csv',self.root/f'V-run{number}.csv']
        for path,headers,rows in (
            (paths[0],['Time (ms)']+[f'{sensor} {axis}' for sensor in ('Accelerometer','Gyroscope') for axis in 'XYZ'],
             [[i*100]+[i+j+number*.2 for j in range(6)] for i in range(count)]),
            (paths[1],['Time (seconds)','Velocity (km/hr)'],[[i*.1,(i*.5+number)*3.6] for i in range(count)])):
            with path.open('w',newline='',encoding='utf-8') as stream:
                writer=csv.writer(stream); writer.writerow(headers); writer.writerows(rows)
        return tuple(paths)

    def holdout(self):
        return evaluate_holdout([self.pair(1)],self.pair(2),window_size=3,n_estimators=3)

    def test_perfect_metrics(self):
        result=evaluate_predictions([0,1,2],[0,1,2])
        self.assertEqual(result['mae_mps'],0)
        self.assertEqual(result['rmse_mps'],0)
        self.assertEqual(result['r2'],1)

    def test_known_metrics(self):
        result=evaluate_predictions([0,1,2],[1,1,4])
        self.assertEqual(result['sample_count'],3)
        self.assertEqual(result['mae_mps'],1)
        self.assertAlmostEqual(result['rmse_mps'],np.sqrt(5/3))
        self.assertEqual(result['bias_mps'],1)
        self.assertEqual(result['median_absolute_error_mps'],1)
        self.assertEqual(result['maximum_absolute_error_mps'],2)
        self.assertEqual(result['mae_kmh'],3.6)
        self.assertAlmostEqual(result['rmse_kmh'],np.sqrt(5/3)*3.6)
        self.assertAlmostEqual(result['r2'],-1.5)

    def test_metric_input_validation(self):
        for truth,pred in (([],[]),([1],[1,2]),([np.nan],[1]),([1],[np.inf]),([-1],[1]),
                           ([True],[1]),(['1'],[1]),([[1]],[[1]])):
            with self.subTest(truth=truth,pred=pred),self.assertRaises(ValueError):
                evaluate_predictions(truth,pred)

    def test_negative_predictions_not_clipped(self):
        self.assertEqual(evaluate_predictions([0],[-1])['bias_mps'],-1)
        self.assertIsNone(evaluate_predictions([1,1],[2,2])['r2'])

    def test_pair_validation_distinct(self):
        runs=validate_pairs([self.pair(1),self.pair(2)])
        self.assertEqual([r['run_id'] for r in runs],['run1','run2'])
        self.assertTrue(Path(runs[0]['smartphone_path']).is_absolute())

    def test_duplicates_overlap_alias(self):
        pair=self.pair(1)
        for pairs in ([pair,pair],[pair,(pair[0].parent/'.'/pair[0].name,pair[1])]):
            with self.assertRaises(ValueError):
                validate_pairs(pairs)
        with self.assertRaises(ValueError):
            evaluate_holdout([pair],pair,n_estimators=2)

    def test_hardlink_and_content_copy_rejected(self):
        first=self.pair(1); second=self.pair(2)
        second[0].write_bytes(first[0].read_bytes())
        with self.assertRaisesRegex(ValueError,'identical content'):
            validate_pairs([first,second])
        alias=self.root/'hardlink.csv'
        try:
            os.link(first[0],alias)
        except OSError:
            self.skipTest('Hardlinks unavailable on temporary filesystem')
        with self.assertRaises(ValueError):
            validate_pairs([first,(alias,second[1])])

    def test_bad_pairs_and_paths(self):
        for bad in ([],['single'],[(1,2)],[('one',)],[(self.root,self.root)]):
            with self.subTest(bad=bad),self.assertRaises(ValueError):
                validate_pairs(bad)
        with self.assertRaises(FileNotFoundError):
            validate_pairs([(self.root/'missing',self.root/'missing2')])
        first,second=self.pair(1),self.pair(2)
        with self.assertRaises(ValueError):
            validate_pairs([(first[0],second[1])])

    def test_holdout_only_trains_training_and_reuses_schema(self):
        first,second=self.pair(1),self.pair(2)
        with patch.object(module,'train_from_pairs',wraps=module.train_from_pairs) as train, \
             patch.object(module,'preprocess_pair',wraps=module.preprocess_pair) as preprocess, \
             patch.object(module,'create_windows',wraps=module.create_windows) as window:
            result=evaluate_holdout([first],second,window_size=3,step_size=2,n_estimators=3)
        self.assertEqual(train.call_count,1)
        self.assertEqual(train.call_args.args[0],[tuple(str(p.resolve()) for p in first)])
        self.assertEqual(preprocess.call_args.args,tuple(str(p.resolve()) for p in second))
        self.assertEqual(preprocess.call_args.kwargs['speed_unit'],'mps')
        self.assertEqual(window.call_args.args[1:4],(3,2,result['model_configuration']['raw_feature_columns']))
        self.assertEqual(result['test_window_count'],6)
        self.assertEqual(result['training_run_ids'],['run1'])
        self.assertEqual(result['test_run_id'],'run2')
        self.assertTrue(all(v is None or np.isfinite(v) for v in result['metrics'].values()))
        row=result['predictions'][0]
        self.assertEqual(row['time_s'],.2)
        self.assertEqual(row['reference_speed_mps'],3)
        self.assertAlmostEqual(row['error_mps'],row['predicted_speed_mps']-row['reference_speed_mps'])

    def test_schema_mismatch_fails(self):
        original=module.create_windows
        def altered(*args,**kwargs):
            result=original(*args,**kwargs); result['feature_names']=list(reversed(result['feature_names'])); return result
        with patch.object(module,'create_windows',side_effect=altered),self.assertRaisesRegex(ValueError,'feature order'):
            self.holdout()

    def test_loro_fold_separation_and_aggregation(self):
        pairs=[self.pair(i,count=12+i) for i in (1,2,3)]
        with patch.object(module,'train_from_pairs',wraps=module.train_from_pairs) as train:
            result=leave_one_run_out(pairs,window_size=3,n_estimators=3)
        self.assertEqual(train.call_count,3)
        self.assertEqual(result['number_of_folds'],3)
        self.assertEqual({f['test_run_id'] for f in result['folds']},{'run1','run2','run3'})
        for fold in result['folds']:
            self.assertNotIn(fold['test_run_id'],fold['training_run_ids'])
            self.assertEqual(len(fold['training_run_ids']),2)
        rows=[r for f in result['folds'] for r in f['predictions']]
        self.assertEqual(result['total_held_out_prediction_count'],len(rows))
        expected=evaluate_predictions([r['reference_speed_mps'] for r in rows],[r['predicted_speed_mps'] for r in rows])
        self.assertEqual(result['aggregate_metrics'],expected)
        self.assertEqual(result['fold_mae_summary']['best_mae_mps'],min(f['metrics']['mae_mps'] for f in result['folds']))
        self.assertEqual(result['fold_mae_summary']['worst_mae_mps'],max(f['metrics']['mae_mps'] for f in result['folds']))

    def test_loro_requires_two(self):
        with self.assertRaisesRegex(ValueError,'two'):
            leave_one_run_out([self.pair(1)])

    def test_speed_band_boundaries(self):
        result=summarize_speed_bands([0,4.99,5,10,15],[0,4.99,5,10,15])
        self.assertEqual([v['sample_count'] for v in result.values()],[2,1,1,1])
        self.assertIsNone(summarize_speed_bands([0],[1])['15+']['mae_mps'])

    def test_stationary_boundaries_false_motion(self):
        result=summarize_stationary_moving([0,.5,.5001],[1,2,3])
        self.assertEqual(result['stationary_sample_count'],2)
        self.assertEqual(result['moving_sample_count'],1)
        self.assertEqual(result['false_motion_rate'],.5)
        self.assertEqual(result['stationary_predicted_speed_mean_mps'],1.5)
        self.assertEqual(result['stationary_mae_mps'],1.25)
        self.assertAlmostEqual(result['moving_mae_mps'],2.4999)
        self.assertIsNone(summarize_stationary_moving([3],[3])['stationary_mae_mps'])

    def test_export_no_overwrite(self):
        result=self.holdout(); json_path=self.root/'out.json'; csv_path=self.root/'out.csv'
        export_results(result,json_output=json_path,predictions_output=csv_path)
        self.assertEqual(json.loads(json_path.read_text())['metrics'],result['metrics'])
        with csv_path.open(newline='',encoding='utf-8') as stream:
            reader=csv.DictReader(stream)
            self.assertEqual(reader.fieldnames,list(module.PREDICTION_FIELDS))
            self.assertEqual(len(list(reader)),result['test_window_count'])
        with self.assertRaises(FileExistsError):
            export_results(result,json_output=json_path)
        with self.assertRaises(ValueError):
            export_results(result,json_output=self.root/'same',predictions_output=self.root/'same')

    def test_cli_required_and_overlap(self):
        pair=self.pair(1)
        for args in ([],['loro'],['holdout','--train-pair',*map(str,pair),'--test-pair',*map(str,pair)]):
            with redirect_stderr(io.StringIO()),self.assertRaises(SystemExit) as error:
                main(args)
            self.assertEqual(error.exception.code,2)

    def test_cli_modes_json_summary(self):
        first,second=self.pair(1),self.pair(2)
        for args in (['holdout','--train-pair',*map(str,first),'--test-pair',*map(str,second)],
                     ['loro','--pair',*map(str,first),'--pair',*map(str,second)]):
            output=io.StringIO()
            with redirect_stdout(output):
                self.assertEqual(main(args+['--window-size','3','--n-estimators','2']),0)
            summary=json.loads(output.getvalue())
            self.assertEqual(summary['metrics_scope'],'HELD-OUT RUN PERFORMANCE')
            self.assertNotIn('predictions',summary)


if __name__ == '__main__':
    unittest.main()
