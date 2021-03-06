require File.expand_path("../helper.rb", __FILE__)
require 'rr'

class QueueTest < QCTest
  include RR::Adapters::TestUnit
  extend RR::Adapters::RRMethods

  def test_enqueue
    QC.enqueue("Klass.method")
  end

  def test_enqueue_if_not_queued_does_not_enqueue_jobs_already_in_queue
    QC.enqueue_if_not_queued("Klass.method", "arg1", "arg2")
    QC.enqueue_if_not_queued("Klass.method", "arg1", "arg2")
    QC.lock
    QC.enqueue_if_not_queued("Klass.method", "arg1", "arg2")
    assert_equal(1, QC.job_count("Klass.method", "arg1", "arg2"))
  end

  def test_enqueue_if_not_queued_does_not_enqueue_jobs_already_in_progress
    QC.enqueue_if_not_queued("Klass.method", "arg1", "arg2")
    job_was_enqueued = !!QC.lock
    assert(job_was_enqueued)

    QC.enqueue_if_not_queued("Klass.method", "arg1", "arg2")
    job_was_enqueued = !!QC.lock
    assert(!job_was_enqueued)
  end

  def test_lock
    QC.enqueue("Klass.method")
    expected = {:id=>"1", :method=>"Klass.method", :args=>[]}
    assert_equal(expected, QC.lock)
  end

  def test_lock_when_empty
    assert_nil(QC.lock)
  end

  def test_count
    QC.enqueue("Klass.method")
    assert_equal(1, QC.count)
  end

  def test_job_count
    #Should return the count of started and unstarted jobs that match both method and arguments
    QC.enqueue("Klass.method", "arg1", "arg2")
    QC.enqueue("Klass.method", "arg1", "arg2")
    QC.enqueue("Klass.method", "arg1", "arg2")
    QC.enqueue("Klass.method", "arg3", "arg4")
    QC.enqueue("Klass.other_method", "arg1", "arg2")
    QC.lock  #start the first job
    assert_equal(3, QC.job_count("Klass.method", "arg1", "arg2"))
  end

  def test_delete
    QC.enqueue("Klass.method")
    assert_equal(1, QC.count)
    QC.delete(QC.lock[:id])
    assert_equal(0, QC.count)
  end

  def test_delete_all
    QC.enqueue("Klass.method")
    QC.enqueue("Klass.method")
    assert_equal(2, QC.count)
    QC.delete_all
    assert_equal(0, QC.count)
  end

  def test_delete_all_by_queue_name
    p_queue = QC::Queue.new("priority_queue")
    s_queue = QC::Queue.new("secondary_queue")
    p_queue.enqueue("Klass.method")
    s_queue.enqueue("Klass.method")
    assert_equal(1, p_queue.count)
    assert_equal(1, s_queue.count)
    p_queue.delete_all
    assert_equal(0, p_queue.count)
    assert_equal(1, s_queue.count)
  end

  def test_queue_instance
    queue = QC::Queue.new("queue_classic_jobs", false)
    queue.enqueue("Klass.method")
    assert_equal(1, queue.count)
    queue.delete(queue.lock[:id])
    assert_equal(0, queue.count)
  end

  def test_repair_after_error
    queue = QC::Queue.new("queue_classic_jobs", false)
    queue.enqueue("Klass.method")
    assert_equal(1, queue.count)

    times_called = 0
    if RUBY_PLATFORM == "java"
      java_import java.sql.SQLException

      stub(QC::Conn).run_prepared_statement do |statement|
        if times_called == 0
          times_called = times_called + 1
          raise java.sql.SQLException.new("Test exception")
        else
          statement.execute
        end
      end
    else
      connection = QC::Conn.connection
      stub(connection).exec {raise PGError}
    end
    assert_raises(QC::Error) { queue.enqueue("Klass.other_method") }
    assert_equal(1, queue.count)
    queue.enqueue("Klass.other_method")
    assert_equal(2, queue.count)
  rescue QC::Error
    QC::Conn.disconnect
    assert false, "Expected to QC repair after connection error"
  end
end
