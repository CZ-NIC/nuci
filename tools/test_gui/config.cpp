#include "config.h"
#include "cmodel.h"

#include <QProcess>
#include <QtXml>
#include <QMessageBox>

#include <cassert>
#include <cstdio>

#define MARK "]]>]]>"
const QString netconfUri("urn:ietf:params:xml:ns:netconf:base:1.0");

Config::Config() :
	process(NULL)
{
	setupUi(this);
}

void Config::on_connectButton_clicked() {
	if (process) {
		disconnectNuci();
	} else {
		connectNuci();
	}
}

void Config::connectNuci() {
	incoming.clear();
	rpcCallbacks.clear();
	// Create and connect the process
	process = new QProcess(this);
	connect(process, SIGNAL(readyReadStandardOutput()), this, SLOT(data()));
	connect(process, SIGNAL(finished(int, QProcess::ExitStatus)), this, SLOT(terminated()));
	connect(process, SIGNAL(readyReadStandardError()), this, SLOT(err()));
	QProcessEnvironment env(QProcessEnvironment::systemEnvironment());
	env.insert("NUCI_TEST_CONFIG_DIR", pathEdit->text());
	process->setProcessEnvironment(env);
	process->start(commandEdit->text());
	// Let it start
	process->waitForStarted(-1);
	// Push the <hello> message there.
	sendData("<?xml version='1.0' encoding='UTF-8'?><hello xmlns='urn:ietf:params:xml:ns:netconf:base:1.0'><capabilities><capability>urn:ietf:params:netconf:base:1.0</capability></capabilities></hello>");
	connectButton->setEnabled(false);
	connectButton->setText("Disconnect");
	expectedExit = true;
}

void Config::disconnectNuci() {
	sendRpc("<close-session/>");
	expectedExit = true;
	process->closeWriteChannel();
	connectButton->setEnabled(false);
	downloadButton->setEnabled(false);
	sendButton->setEnabled(false);
	storeButton->setEnabled(false);
}

void Config::data() {
	// Some data arrived from remote
	incoming += process->readAll();
	int index;
	while ((index = incoming.indexOf(MARK)) != -1) {
		// Extract the message and drop it from the front
		QByteArray message(incoming.data(), index);
		incoming.remove(0, index + strlen(MARK));
		printf("Received XML:\n%s\n\n", message.data());

		handleMessage(message);
	}
}

void Config::terminated() {
	connectButton->setEnabled(true);
	connectButton->setText("Connect");
	if (process->exitStatus() == QProcess::CrashExit) {
		QMessageBox::warning(this, "NUCI Crash", "NUCI terminated with crash exit code");
		expectedExit = true;
	}
	if (!expectedExit) {
		QMessageBox::warning(this, "NUCI Crash", "NUCI terminated, but I didn't expect it to");
	}
	process->deleteLater();
	process = NULL;
}

void Config::sendData(const QString &data) {
	QByteArray cp(data.toLocal8Bit());
	printf("Sending XML message:\n%s\n\n", cp.data());
	cp.append("\n" MARK);
	while (!cp.isEmpty())
		writeData(process, cp);
}

void Config::writeData(QProcess *process, QByteArray &array) {
	qint64 written = process->write(array);
	assert(written > 0);
	array.remove(0, written);
}

void Config::handleMessage(const QByteArray &message) {
	QDomDocument xml;
	bool ok = xml.setContent(message, true);
	assert(ok);
	/*
	 * We don't check the namespace here. Qt seems to return empty string
	 * (I must be doing something wrong, obviously), and this is dirty
	 * test tool only anyway.
	 */
	const QString &name(xml.documentElement().tagName());
	if (name == "hello") {
		handleHello(xml);
		return;
	} else if (name == "rpc-reply") {
		handleRpc(xml);
		return;
	}
	assert(false);
}

void Config::handleRpc(QDomDocument &rpc) {
	QString sid(rpc.documentElement().attribute("message-id"));
	bool ok = true;
	size_t id = sid.toULongLong(&ok);
	assert(ok);
	if (rpcCallbacks.contains(id)) {
		(this->*rpcCallbacks[id])(rpc, id);
		rpcCallbacks.remove(id);
	}
}

void Config::handleHello(QDomDocument &) {
	connectButton->setEnabled(true);
	downloadButton->setEnabled(true);
	sendButton->setEnabled(!xmlEdit->toPlainText().isEmpty());
	storeButton->setEnabled(!xmlEdit->toPlainText().isEmpty());
	downloadButton->click();
}

size_t Config::sendRpc(const QString &xml, RpcCallback callback) {
	static size_t id = 0;
	sendData(QString("<?xml version='1.0' encoding='UTF-8'?><rpc xmlns='urn:ietf:params:xml:ns:netconf:base:1.0' message-id='%1'>%2</rpc>").arg(++id).arg(xml));
	if (callback) {
		rpcCallbacks[id] = callback;
	}
	return id;
}

void Config::on_downloadButton_clicked() {
	sendRpc("<get-config><source><running/></source></get-config>", &Config::configDownloaded);
}

void Config::configDownloaded(QDomDocument &rpc, size_t) {
	printf("Configuration downloaded\n");
	// FIXME: This leaks
	model = new ConfigModel(rpc);
	configView->setModel(model);
	on_configView_clicked();
}

void Config::on_configView_clicked() {
	editWidget->setEnabled(process && configView->currentIndex().isValid());
}

void Config::on_removeButton_clicked() {
	prepareXml("remove", false, false);
}

void Config::on_replaceButton_clicked() {
	prepareXml("replace", true, true);
}

void Config::on_mergeButton_clicked() {
	prepareXml("", false, true);
}

void Config::on_createButton_clicked() {
	prepareXml("create", true, true);
}

void Config::on_sendButton_clicked() {
	sendRpc(xmlEdit->toPlainText(), &Config::editResponse);
}

void Config::prepareXml(const QString &operation, bool subnodes, bool content) {
	QDomDocument doc;
	doc.setContent(QString("<edit-config><target><running/></target><config><uci xmlns='http://www.nic.cz/ns/router/uci-raw'/></config></edit-config>"));
	QDomElement node(model->getNode(configView->currentIndex(), doc, subnodes, content));
	node.setAttribute("xmlns:nc", netconfUri);
	if (!operation.isEmpty()) {
		node.setAttribute("nc:operation", operation);
	}
	xmlEdit->setText(doc.toString(4));
	sendButton->setEnabled(process);
	storeButton->setEnabled(process);
}

void Config::editResponse(QDomDocument &rpc, size_t) {
	const QDomNodeList &errors(rpc.elementsByTagNameNS(netconfUri, "rpc-error"));
	if (errors.size()) {
		const QString &text(errors.at(0).namedItem("error-message").toElement().text());
		QMessageBox::warning(this, "RPC error", text);
	}
	// Get the new version of config. It may have changed.
	downloadButton->click();
}

void Config::on_storeButton_clicked() {
	QProcess dumper;
	dumper.start("./tools/test_gui/dump-test");
	dumper.waitForStarted();
	QByteArray xml(xmlEdit->toPlainText().toLocal8Bit());
	while (!xml.isEmpty())
		writeData(&dumper, xml);
	dumper.closeWriteChannel();
	dumper.waitForFinished();
	const QByteArray &dirA(dumper.readAll());
	const QString &dir(QString(dirA).trimmed());
	size_t id(sendRpc(xmlEdit->toPlainText(), &Config::dumpResult));
	dirs[id] = dir;
}

void Config::dumpResult(QDomDocument &rpc, size_t id) {
	const QString dir(dirs[id]);
	dirs.remove(id);
	QProcess dumper;
	dumper.start("./tools/test_gui/dump-test-post", QStringList() << dir);
	printf("Started with dir %s\n", dir.toLocal8Bit().data());
	rpc.documentElement().setAttribute("message-id", "ID");
	QByteArray xml(rpc.toString().toLocal8Bit());
	while (!xml.isEmpty())
		writeData(&dumper, xml);
	dumper.closeWriteChannel();
	dumper.waitForFinished();
}

void Config::err() {
	const QByteArray e(process->readAllStandardError());
	fputs(e.data(), stderr);
}
