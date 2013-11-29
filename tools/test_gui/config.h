/*
 * Copyright 2013, CZ.NIC z.s.p.o. (http://www.nic.cz/)
 *
 * This file is part of NUCI configuration server.
 *
 * NUCI is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 *  (at your option) any later version.
 *
 * NUCI is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with NUCI.  If not, see <http://www.gnu.org/licenses/>.
 */

#ifndef CONFIG_H
#define CONFIG_H

#include <QMainWindow>

#include "ui_config.h"

class QProcess;
class QDomDocument;
class ConfigModel;

class Config : public QMainWindow, private Ui::Config {
	Q_OBJECT;
public:
	typedef void (Config::*RpcCallback)(QDomDocument &rpc, size_t id);
	Config();
private slots:
	void on_connectButton_clicked();
	void on_downloadButton_clicked();
	void on_removeButton_clicked();
	void on_mergeButton_clicked();
	void on_replaceButton_clicked();
	void on_createButton_clicked();
	void on_configView_clicked();
	void on_sendButton_clicked();
	void on_storeButton_clicked();
	void data();
	void err();
	void terminated();
private:
	void connectNuci();
	void disconnectNuci();
	void sendData(const QString &data);
	void writeData(QProcess *process, QByteArray &data);
	void handleMessage(const QByteArray &data);
	void handleHello(QDomDocument &hello);
	void handleRpc(QDomDocument &rpc);
	size_t sendRpc(const QString &xml, RpcCallback callback = NULL);
	void configDownloaded(QDomDocument &rpc, size_t id);
	void editResponse(QDomDocument &rpc, size_t id);
	void dumpResult(QDomDocument &rpc, size_t id);
	void prepareXml(const QString &operation, bool subnodes, bool content);
	void openModel(const QModelIndex &index = QModelIndex());
	QProcess *process;
	QByteArray incoming;
	QHash<size_t, RpcCallback> rpcCallbacks;
	QHash<size_t, QString> dirs;
	ConfigModel *model;
	bool expectedExit;
};

#endif
